#!/usr/bin/env bash
# diff_layers.sh — Compare layer bindings across boards
#
# Usage:
#   ./scripts/diff_layers.sh                         Stub status table (which layers need filling)
#   ./scripts/diff_layers.sh <layer>                 Show Go60 reference bindings (numbered by key position)
#   ./scripts/diff_layers.sh <layer> <board>         Show one board's bindings
#   ./scripts/diff_layers.sh <layer> <board1> <board2>  Diff two boards side by side
#
# Boards:  go60  glove80  slicemk
# Layers:  base  typing  autoshift  hrm_left_pinky  hrm_left_ring  ...  magic
#          (run with no args to see full layer list in the stub status table)

set -euo pipefail

REPO_ROOT="$(cd "$(dirname "$0")/.." && pwd)"

LAYER_NAMES=(
  base typing autoshift
  hrm_left_pinky hrm_left_ring hrm_left_middy hrm_left_index
  hrm_right_pinky hrm_right_ring hrm_right_middy hrm_right_index
  cursor keypad symbol
  mouse mouse_slow mouse_fast mouse_warp
  magic
)

if [[ -t 1 ]]; then
  RED='\033[0;31m'; GREEN='\033[0;32m'; YELLOW='\033[1;33m'
  CYAN='\033[0;36m'; BOLD='\033[1m'; DIM='\033[2m'; NC='\033[0m'
else
  RED=''; GREEN=''; YELLOW=''; CYAN=''; BOLD=''; DIM=''; NC=''
fi

usage() {
  cat <<EOF

${BOLD}diff_layers.sh${NC} — Compare layer bindings across boards

${BOLD}Usage:${NC}
  $0                              Stub status table
  $0 <layer>                      Show Go60 reference bindings (numbered by key pos)
  $0 <layer> <board>              Show one board's layer bindings
  $0 <layer> <board1> <board2>    Diff two boards' bindings for a layer

${BOLD}Boards:${NC}  go60  glove80  slicemk

${BOLD}Layers:${NC}
  base  typing  autoshift
  hrm_left_{pinky,ring,middy,index}
  hrm_right_{pinky,ring,middy,index}
  cursor  keypad  symbol
  mouse  mouse_slow  mouse_fast  mouse_warp
  magic

EOF
}


layer_file() {
  echo "$REPO_ROOT/boards/$1/layers/$2.dtsi"
}

# Extract bindings from a layer file: one binding (with params) per line.
# Strips block comments, extracts bindings = < ... >; block, splits on &.
extract_bindings() {
  local file="$1"
  if [[ ! -f "$file" ]]; then
    echo "(file not found: $file)"
    return
  fi
  perl -0777 -pe 's|/\*.*?\*/||gs' "$file" \
    | awk '/bindings = </{f=1;next} f && />;/{f=0;next} f{print}' \
    | tr -s '[:space:]' ' ' \
    | sed 's/&/\n\&/g' \
    | sed 's/^[[:space:]]*//; s/[[:space:]]*$//' \
    | grep -v '^[[:space:]]*$' \
    | grep '^&'
}

# Check if a layer is all-&trans (stub)
is_stub() {
  local file="$1"
  [[ -f "$file" ]] || { echo "MISSING"; return; }
  local non_trans
  non_trans=$(extract_bindings "$file" | grep -cv '^&trans$' || true)
  if [[ "$non_trans" -eq 0 ]]; then
    echo "stub"
  else
    local total
    total=$(extract_bindings "$file" | wc -l | tr -d ' ')
    echo "$((total - non_trans)) trans / $total"
  fi
}

# Print bindings numbered by key position (0-indexed)
print_numbered() {
  local file="$1"
  extract_bindings "$file" | awk '{printf "  %3d  %s\n", NR-1, $0}'
}

# ══════════════════════════════════════════════════════════════
# No args → stub status table
# ══════════════════════════════════════════════════════════════
if [[ $# -eq 0 ]]; then
  printf "\n${BOLD}%-24s  %-20s  %-20s  %-20s${NC}\n" \
         "Layer" "go60" "glove80" "slicemk"
  printf "%-24s  %-20s  %-20s  %-20s\n" \
         "────────────────────────" "────────────────────" \
         "────────────────────" "────────────────────"

  for layer in "${LAYER_NAMES[@]}"; do
    g60=$(is_stub "$(layer_file go60 "$layer")")
    g80=$(is_stub "$(layer_file glove80 "$layer")")
    smk=$(is_stub "$(layer_file slicemk "$layer")")

    # Colorise each status
    colorise() {
      local s="$1"
      case "$s" in
        stub)    printf "${YELLOW}%-20s${NC}" "$s" ;;
        MISSING) printf "${RED}%-20s${NC}" "$s" ;;
        *)       printf "${GREEN}%-20s${NC}" "$s" ;;
      esac
    }

    printf "%-24s  " "$layer"
    colorise "$g60"
    printf "  "
    colorise "$g80"
    printf "  "
    colorise "$smk"
    printf "\n"
  done
  echo
  printf "${DIM}Run '$(basename "$0") <layer>' to see Go60 reference bindings for any layer.${NC}\n\n"
  exit 0
fi

# ══════════════════════════════════════════════════════════════
# 1 arg → show Go60 reference bindings (numbered)
# ══════════════════════════════════════════════════════════════
if [[ $# -eq 1 ]]; then
  layer="$1"
  file=$(layer_file go60 "$layer")
  if [[ ! -f "$file" ]]; then
    printf "${RED}Error:${NC} layer '%s' not found at %s\n" "$layer" "$file"
    exit 1
  fi
  printf "\n${BOLD}Go60 reference — %s${NC}  ${DIM}(%s)${NC}\n" "$layer" "$file"
  printf "${DIM}  pos  binding${NC}\n"
  print_numbered "$file"
  echo
  exit 0
fi

# ══════════════════════════════════════════════════════════════
# 2 args → show one board's bindings (numbered)
# ══════════════════════════════════════════════════════════════
if [[ $# -eq 2 ]]; then
  layer="$1" board="$2"
  file=$(layer_file "$board" "$layer")
  if [[ ! -f "$file" ]]; then
    printf "${RED}Error:${NC} %s/%s not found\n" "$board" "$layer"
    exit 1
  fi
  printf "\n${BOLD}%s — %s${NC}  ${DIM}(%s)${NC}\n" "$board" "$layer" "$file"
  printf "${DIM}  pos  binding${NC}\n"
  print_numbered "$file"
  echo
  exit 0
fi

# ══════════════════════════════════════════════════════════════
# 3 args → diff two boards
# ══════════════════════════════════════════════════════════════
if [[ $# -eq 3 ]]; then
  layer="$1" board_a="$2" board_b="$3"
  file_a=$(layer_file "$board_a" "$layer")
  file_b=$(layer_file "$board_b" "$layer")

  [[ -f "$file_a" ]] || { printf "${RED}Error:${NC} %s/%s not found\n" "$board_a" "$layer"; exit 1; }
  [[ -f "$file_b" ]] || { printf "${RED}Error:${NC} %s/%s not found\n" "$board_b" "$layer"; exit 1; }

  tmp_a=$(mktemp)
  tmp_b=$(mktemp)
  trap 'rm -f "$tmp_a" "$tmp_b"' EXIT

  extract_bindings "$file_a" > "$tmp_a"
  extract_bindings "$file_b" > "$tmp_b"

  count_a=$(wc -l < "$tmp_a" | tr -d ' ')
  count_b=$(wc -l < "$tmp_b" | tr -d ' ')

  printf "\n${BOLD}diff %s vs %s — %s${NC}\n" "$board_a" "$board_b" "$layer"
  printf "${DIM}  %s: %s bindings (%s)${NC}\n" "$board_a" "$count_a" "$file_a"
  printf "${DIM}  %s: %s bindings (%s)${NC}\n\n" "$board_b" "$count_b" "$file_b"

  if diff -q "$tmp_a" "$tmp_b" > /dev/null 2>&1; then
    printf "${GREEN}  Identical bindings.${NC}\n\n"
    exit 0
  fi

  # Colorise diff output if in a terminal
  if [[ -t 1 ]]; then
    diff --unified=2 --label "$board_a" --label "$board_b" "$tmp_a" "$tmp_b" \
      | awk "
          /^\-\-\-/ { print \"${BOLD}\" \$0 \"${NC}\"; next }
          /^\+\+\+/ { print \"${BOLD}\" \$0 \"${NC}\"; next }
          /^@@/     { print \"${CYAN}\" \$0 \"${NC}\"; next }
          /^\-/     { print \"${RED}\" \$0 \"${NC}\"; next }
          /^\+/     { print \"${GREEN}\" \$0 \"${NC}\"; next }
          { print }
      " || true
  else
    diff --unified=2 --label "$board_a" --label "$board_b" "$tmp_a" "$tmp_b" || true
  fi
  echo
  exit 0
fi

usage
exit 1
