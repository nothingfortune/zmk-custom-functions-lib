#!/usr/bin/env bash

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

# Rewrite the bindings block of a dtsi file with a new set of binding groups
write_bindings() {
  local file="$1"
  local -n _new="$2"

  local indent
  indent=$(grep -m1 'bindings' "$file" | sed -E 's/(^[[:space:]]*).*/\1/')

  local blk
  blk=$(mktemp)
  {
    printf '%sbindings = <\n' "$indent"
    local line="${indent}  "
    for b in "${_new[@]}"; do
      if (( ${#line} + ${#b} + 1 > 100 )); then
        printf '%s\n' "$line"
        line="${indent}  "
      fi
      line+="$b "
    done
    printf '%s\n' "$line"
    printf '%s>;\n' "$indent"
  } > "$blk"

  awk -v blk="$blk" '
    BEGIN { skip = 0 }
    /bindings[[:space:]]*=/ {
      while ((getline ln < blk) > 0) print ln
      close(blk)
      skip = 1; next
    }
    skip && />[[:space:]]*;/ { skip = 0; next }
    !skip { print }
  ' "$file" > "${file}.tmp"

  rm -f "$blk"
  mv "${file}.tmp" "$file"
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

  local go_b tgt_b
  parse_bindings "$go_file"  go_b
  parse_bindings "$tgt_file" tgt_b

  [[ ${#go_b[@]}  -eq 0 ]] && { echo "  skip (no go60 bindings): $name";   return; }
  [[ ${#tgt_b[@]} -eq 0 ]] && { echo "  skip (no target bindings): $name"; return; }

  local n=0
  for src in "${!_fwd[@]}"; do
    local dst="${_fwd[$src]}"
    if (( src < ${#go_b[@]} && dst < ${#tgt_b[@]} )); then
      tgt_b[$dst]="${go_b[$src]}"
      n=$(( n + 1 ))
    fi
  done

  printf '  %-32s %d positions updated\n' "$name" "$n"
  write_bindings "$tgt_file" tgt_b
}

# ── main ─────────────────────────────────────────────────────────────────────

declare -A fwd_glove80 fwd_slicemk
load_map "$TRANS_DIR/go60_to_glove80.txt" fwd_glove80
load_map "$TRANS_DIR/go60_to_slicemk.txt" fwd_slicemk

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
