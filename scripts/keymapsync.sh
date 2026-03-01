
#!/usr/bin/env bash
# Re-exec with bash 4+ if the system shell is too old (macOS ships bash 3.2)
if (( BASH_VERSINFO[0] < 4 )); then
  for _b in /opt/homebrew/bin/bash /usr/local/bin/bash; do
    [[ -x "$_b" ]] && exec "$_b" "$0" "$@"
  done
  echo "Error: bash 4+ required. Install via: brew install bash" >&2; exit 1
fi
set -euo pipefail

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"

GO60_DIR="$REPO_ROOT/boards/go60/layers"
GLOVE80_DIR="$REPO_ROOT/boards/glove80/layers"
SLICEMK_DIR="$REPO_ROOT/boards/slicemk/layers"
TRANS_DIR="$REPO_ROOT/boards/translations"

# Load a "src dst" translation map into an associative array (skips # comments)
load_map() {
  local file="$1"
  local -n _map="$2"
  _map=()
  while IFS=' ' read -r src dst; do
    [[ -z "$src" || "$src" == \#* ]] && continue
    _map[$src]=$dst
  done < "$file"
}

# Extract and parse the bindings block from a dtsi file into an indexed array.
# Each element is one complete ZMK binding: "&behavior [param1 [param2]]"
# Groups tokens by & prefix, so both zero-param macros (&gresc, &upDownArrows)
# and multi-param behaviors (&kp X, &HRM_left_pinky_v1B_TKZ LGUI A) are one element.
parse_bindings() {
  local file="$1"
  local -n _b="$2"
  _b=()

  # Extract raw content between "bindings = <" and ">;", strip /* */ block comments
  local raw
  raw=$(awk '
    /bindings[[:space:]]*=/ {
      in_b = 1
      sub(/.*bindings[[:space:]]*=[[:space:]]*<[[:space:]]*/, "")
      if (/>[[:space:]]*;/) { sub(/>[[:space:]]*;.*/, ""); print; in_b = 0; next }
      print; next
    }
    in_b {
      if (/>[[:space:]]*;/) { sub(/>[[:space:]]*;.*/, ""); print; in_b = 0 }
      else { print }
    }
  ' "$file" | perl -pe 's|/\*.*?\*/||g')

  # Each token starting with & begins a new binding; subsequent non-& tokens are its params
  local current=""
  while IFS= read -r token; do
    [[ -z "$token" ]] && continue
    if [[ "$token" == "&"* ]]; then
      [[ -n "$current" ]] && _b+=("$current")
      current="$token"
    else
      current+=" $token"
    fi
  done < <(tr -s '[:space:]' '\n' <<< "$raw")
  [[ -n "$current" ]] && _b+=("$current")
}

# Parse the slot width (binding text + trailing H-space to next & on same line)
# for every binding in a dtsi file's bindings block.  Widths for end-of-line
# bindings equal just their binding text length (no trailing space to measure).
parse_widths() {
  local file="$1"
  local -n _pw="$2"
  _pw=()

  local raw
  raw=$(awk '
    /bindings[[:space:]]*=/ {
      in_b = 1
      sub(/.*bindings[[:space:]]*=[[:space:]]*<[[:space:]]*/, "")
      if (/>[[:space:]]*;/) { sub(/>[[:space:]]*;.*/, ""); print; in_b = 0; next }
      print; next
    }
    in_b {
      if (/>[[:space:]]*;/) { sub(/>[[:space:]]*;.*/, ""); print; in_b = 0 }
      else { print }
    }
  ' "$file" | perl -pe 's|/\*.*?\*/||g')

  local plscript
  plscript=$(mktemp /tmp/keymapsync_XXXXXX.pl)
  cat > "$plscript" << 'PLEOF'
use strict; use warnings;
my $block = do { local $/; <STDIN> };
my $len = length($block);
my @widths;
my $i = 0;
while ($i < $len) {
    if (substr($block,$i,2) eq '/*') {
        my $e = index($block,'*/',$i+2); $i = ($e>=0) ? $e+2 : $len; next;
    }
    if (substr($block,$i,2) eq '//') {
        my $e = index($block,"\n",$i+2); $i = ($e>=0) ? $e+1 : $len; next;
    }
    if (substr($block,$i,1) =~ /\s/) { $i++; next; }
    if (substr($block,$i,1) eq '&') {
        my $start = $i;
        while ($i<$len && substr($block,$i,1)!~/\s/
               && substr($block,$i,2) ne '/*' && substr($block,$i,2) ne '//') { $i++ }
        my $end = $i;
        PARAM: while (1) {
            my $j = $i;
            while ($j<$len && substr($block,$j,1) =~ /[ \t]/) { $j++ }
            last PARAM if $j>=$len || substr($block,$j,1) eq '&'
                       || substr($block,$j,2) eq '/*' || substr($block,$j,2) eq '//'
                       || substr($block,$j,1) =~ /[\r\n]/;
            $i = $j;
            while ($i<$len && substr($block,$i,1)!~/\s/
                   && substr($block,$i,2) ne '/*' && substr($block,$i,2) ne '//') { $i++ }
            $end = $i;
        }
        my $slot_end = $end;
        { my $j = $end;
          while ($j<$len && substr($block,$j,1) =~ /[ \t]/) { $j++ }
          if ($j<$len && substr($block,$j,1) !~ /[\r\n]/
              && substr($block,$j,2) ne '/*' && substr($block,$j,2) ne '//'
              && substr($block,$j,1) eq '&') { $slot_end = $j; }
        }
        push @widths, $slot_end - $start;
    } else {
        while ($i<$len && substr($block,$i,1)!~/\s/) { $i++ }
    }
}
print join("\n", @widths), "\n";
PLEOF

  local w
  while IFS= read -r w; do
    [[ -n "$w" ]] && _pw+=("$w")
  done < <(perl "$plscript" <<< "$raw")
  rm -f "$plscript"
}

# Update only the bindings that changed, preserving all comments and whitespace.
write_bindings() {
  local file="$1"
  local -n _new="$2"

  local plscript
  plscript=$(mktemp /tmp/keymapsync_XXXXXX.pl)
  cat > "$plscript" << 'PLEOF'
use strict;
use warnings;
my ($file, @new_bindings) = @ARGV;

# Decode "min_width:binding_text" format.  min_width is the minimum slot width
# (from the go60 source) to use for this position, ensuring the target file's
# column alignment is at least as wide as the canonical source.
my @min_widths;
for my $b (@new_bindings) {
    if ($b =~ /^(\d+):(.+)$/) { push @min_widths, $1+0; $b = $2; }
    else                       { push @min_widths, 0; }
}

open(my $fh, '<', $file) or die "Cannot open $file: $!";
my $content = do { local $/; <$fh> };
close($fh);

# Locate the bindings block
$content =~ /bindings\s*=\s*<(.*?)>;/s or exit 0;
my ($bs, $be) = ($-[1], $+[1]);
my $block = $1;

# Parse the character span of each binding token in the original block.
# Skips /* */ and // comments; treats horizontal-whitespace-only gaps as
# parameter separators (stops at newlines so params stay on their line).
my @spans;
my $i = 0;
my $len = length($block);
while ($i < $len) {
    if (substr($block, $i, 2) eq '/*') {
        my $e = index($block, '*/', $i + 2);
        $i = ($e >= 0) ? $e + 2 : $len; next;
    }
    if (substr($block, $i, 2) eq '//') {
        my $e = index($block, "\n", $i + 2);
        $i = ($e >= 0) ? $e + 1 : $len; next;
    }
    if (substr($block, $i, 1) =~ /\s/) { $i++; next; }
    if (substr($block, $i, 1) eq '&') {
        my $start = $i;
        while ($i < $len
               && substr($block, $i, 1) !~ /\s/
               && substr($block, $i, 2) ne '/*'
               && substr($block, $i, 2) ne '//') { $i++; }
        my $end = $i;
      PARAM: while (1) {
            my $j = $i;
            while ($j < $len && substr($block, $j, 1) =~ /[ \t]/) { $j++; }
            last PARAM if $j >= $len;
            last PARAM if substr($block, $j, 1) eq '&';
            last PARAM if substr($block, $j, 2) eq '/*';
            last PARAM if substr($block, $j, 2) eq '//';
            last PARAM if substr($block, $j, 1) =~ /[\r\n]/;
            $i = $j;
            while ($i < $len
                   && substr($block, $i, 1) !~ /\s/
                   && substr($block, $i, 2) ne '/*'
                   && substr($block, $i, 2) ne '//') { $i++; }
            $end = $i;
        }
        # Find slot_end: end of trailing horizontal whitespace before next & on same line.
        # Used to maintain column alignment when replacing bindings.
        my $slot_end = $end;
        {
            my $j = $end;
            while ($j < $len && substr($block, $j, 1) =~ /[ \t]/) { $j++; }
            if (   $j < $len
                && substr($block, $j, 1) !~ /[\r\n]/
                && substr($block, $j, 2) ne '/*'
                && substr($block, $j, 2) ne '//'
                && substr($block, $j, 1) eq '&') {
                $slot_end = $j;
            }
        }
        push @spans, [$start, $end, $slot_end];
    } else {
        while ($i < $len && substr($block, $i, 1) !~ /\s/) { $i++; }
    }
}

# Build list of replacements.
# For mid-line bindings (followed by another & on the same line): always replace the full
# slot (binding text + trailing whitespace) to maintain column alignment, even when the
# binding text itself is unchanged.
# For end-of-line bindings: only replace when the text changed.
my @reps;
for my $idx (0 .. $#spans) {
    next if $idx >= scalar(@new_bindings);
    my ($s, $e, $slot_end) = @{$spans[$idx]};
    my $old = substr($block, $s, $e - $s); $old =~ s/\s+/ /g; $old =~ s/^\s+|\s+$//g;
    my $new = $new_bindings[$idx];         $new =~ s/^\s+|\s+$//g;
    if ($slot_end > $e) {
        # Mid-line: replace binding + trailing whitespace, padding new text to slot width.
        # Use the larger of the current file's slot width and the go60 source min width.
        my $slot_width = $slot_end - $s;
        my $min_w = $min_widths[$idx] // 0;
        $slot_width = $min_w if $min_w > $slot_width;
        my $pad = $slot_width - length($new);
        $pad = 1 if $pad < 1;
        push @reps, [$bs + $s, $bs + $slot_end, $new . (' ' x $pad)];
    } elsif ($old ne $new) {
        # End-of-line: only replace when binding text changed.
        push @reps, [$bs + $s, $bs + $e, $new];
    }
}

exit 0 unless @reps;

my $original = $content;

# Apply in reverse order so earlier offsets stay valid
for my $r (sort { $b->[0] <=> $a->[0] } @reps) {
    my ($s, $e, $n) = @$r;
    substr($content, $s, $e - $s) = $n;
}

# Only write the file when content actually changed
if ($content ne $original) {
    open($fh, '>', $file) or die "Cannot write $file: $!";
    print $fh $content;
    close($fh);
}
PLEOF

  perl "$plscript" "$file" "${_new[@]}"
  rm -f "$plscript"
}

# Apply a positional translation from go60 to one target board layer file.
# Only positions present in the translation map are updated; all
# target-board-only positions are left untouched.
sync_layer() {
  local go_file="$1"
  local tgt_file="$2"
  local -n _fwd="$3"   # associative: go60_idx -> target_idx
  local name
  name=$(basename "$go_file")

  [[ ! -f "$tgt_file" ]] && { echo "  skip (missing target): $name"; return; }

  local go_b go_sw tgt_b
  parse_bindings "$go_file"  go_b
  parse_widths   "$go_file"  go_sw   # slot widths from the canonical go60 source
  parse_bindings "$tgt_file" tgt_b

  [[ ${#go_b[@]}  -eq 0 ]] && { echo "  skip (no go60 bindings): $name";   return; }
  [[ ${#tgt_b[@]} -eq 0 ]] && { echo "  skip (no target bindings): $name"; return; }

  # Build encoded array: "min_width:binding_text"
  # Non-mapped (target-only) positions get min_width=0 (preserve current slot width).
  local tgt_enc=()
  for idx in "${!tgt_b[@]}"; do
    tgt_enc[$idx]="0:${tgt_b[$idx]}"
  done

  local n=0
  for src in "${!_fwd[@]}"; do
    local dst="${_fwd[$src]}"
    if (( src < ${#go_b[@]} && dst < ${#tgt_b[@]} )); then
      local gw="${go_sw[$src]:-0}"
      tgt_enc[$dst]="${gw}:${go_b[$src]}"
      n=$(( n + 1 ))
    fi
  done

  printf '  %-32s %d positions updated\n' "$name" "$n"
  write_bindings "$tgt_file" tgt_enc
}

# ── main ─────────────────────────────────────────────────────────────────────

declare -A fwd_glove80 fwd_slicemk
load_map "$TRANS_DIR/go60_to_glove80.map" fwd_glove80
load_map "$TRANS_DIR/go60_to_slicemk.map" fwd_slicemk

echo "==> go60 → glove80"
for f in "$GO60_DIR"/*.dtsi; do
  sync_layer "$f" "$GLOVE80_DIR/$(basename "$f")" fwd_glove80
done

echo
echo "==> go60 → slicemk"
for f in "$GO60_DIR"/*.dtsi; do
  sync_layer "$f" "$SLICEMK_DIR/$(basename "$f")" fwd_slicemk
done

echo
echo "Done."
