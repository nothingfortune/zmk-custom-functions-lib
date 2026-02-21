#!/usr/bin/env bash
# validation.sh — Validate the zmk-custom-functions-lib repo structure
#
# Usage: ./scripts/validation.sh
# Exit code: 0 = all pass, 1 = one or more failures

set -euo pipefail

REPO_ROOT="$(cd "$(dirname "$0")/.." && pwd)"
PASS=0
FAIL=0
WARN=0

if [[ -t 1 ]]; then
  RED='\033[0;31m'; GREEN='\033[0;32m'; YELLOW='\033[1;33m'
  BOLD='\033[1m'; NC='\033[0m'
else
  RED=''; GREEN=''; YELLOW=''; BOLD=''; NC=''
fi

pass() { printf "  ${GREEN}PASS${NC}  %s\n" "$1"; PASS=$((PASS + 1)); }
fail() { printf "  ${RED}FAIL${NC}  %s\n" "$1"; FAIL=$((FAIL + 1)); }
warn() { printf "  ${YELLOW}WARN${NC}  %s\n" "$1"; WARN=$((WARN + 1)); }
section() { printf "\n${BOLD}── %s${NC}\n" "$1"; }


LAYER_NAMES=(
  base typing autoshift
  hrm_left_pinky hrm_left_ring hrm_left_middy hrm_left_index
  hrm_right_pinky hrm_right_ring hrm_right_middy hrm_right_index
  cursor keypad symbol
  mouse mouse_slow mouse_fast mouse_warp
  magic
)

# Count & binding tokens in a layer file (strips block comments)
count_bindings() {
  local file="$1"
  perl -0777 -pe 's|/\*.*?\*/||gs' "$file" \
    | awk '/bindings = </{f=1;next} f && />;/{f=0;next} f{print}' \
    | grep -oE '&[A-Za-z][A-Za-z0-9_]*' \
    | wc -l \
    | tr -d ' '
}

# Count non-&trans binding tokens in a layer file
count_non_trans() {
  local file="$1"
  perl -0777 -pe 's|/\*.*?\*/||gs' "$file" \
    | awk '/bindings = </{f=1;next} f && />;/{f=0;next} f{print}' \
    | grep -oE '&[A-Za-z][A-Za-z0-9_]*' \
    | grep -cv '^&trans$' \
    || true
}

# ══════════════════════════════════════════════════════════════
section "1. Required files"
# ══════════════════════════════════════════════════════════════

REQUIRED_FILES=(
  shared/layers.dtsi
  shared/macros.dtsi
  shared/behaviors.dtsi
  shared/modMorphs.dtsi
  shared/autoshift.dtsi
  shared/bluetooth.dtsi
  shared/magic.dtsi
  shared/homeRowMods/hrm_timings.dtsi
  shared/homeRowMods/hrm_macros.dtsi
  shared/homeRowMods/hrm_behaviors.dtsi
  shared/combos/combos_common.dtsi
  shared/combos/combos_fkeys.dtsi
  boards/go60/positions.dtsi
  boards/go60/position_groups.dtsi
  boards/go60/board_meta.dtsi
  boards/go60/go60.keymap
  boards/go60/go60.conf
  boards/glove80/positions.dtsi
  boards/glove80/position_groups.dtsi
  boards/glove80/board_meta.dtsi
  boards/glove80/glove80.keymap
  boards/glove80/glove80.conf
  boards/slicemk/positions.dtsi
  boards/slicemk/position_groups.dtsi
  boards/slicemk/board_meta.dtsi
  boards/slicemk/slicemk.keymap
  boards/slicemk/slicemk.conf
  config/west.yml
  config/slicemk_ergodox.keymap
  config/slicemk_ergodox_leftcentral.conf
  build/go60.nix
  build/glove80.nix
  build.yaml
  .github/workflows/build.yml
)

for f in "${REQUIRED_FILES[@]}"; do
  if [[ -f "$REPO_ROOT/$f" ]]; then
    pass "$f"
  else
    fail "$f  ← MISSING"
  fi
done

# ══════════════════════════════════════════════════════════════
section "2. Layer files per board (expect 19)"
# ══════════════════════════════════════════════════════════════

for board in go60 glove80 slicemk; do
  missing=()
  for layer in "${LAYER_NAMES[@]}"; do
    [[ -f "$REPO_ROOT/boards/$board/layers/$layer.dtsi" ]] || missing+=("$layer")
  done
  if [[ ${#missing[@]} -eq 0 ]]; then
    pass "boards/$board/layers/ — all 19 layer files present"
  else
    fail "boards/$board/layers/ — missing: ${missing[*]}"
  fi
done

# ══════════════════════════════════════════════════════════════
section "3. Position counts"
# ══════════════════════════════════════════════════════════════

check_positions() {
  local board="$1" expected="$2"
  local file="$REPO_ROOT/boards/$board/positions.dtsi"
  local count
  count=$(grep -c '^#define POS_' "$file" 2>/dev/null || echo 0)
  if [[ "$count" -eq "$expected" ]]; then
    pass "boards/$board/positions.dtsi — $count positions"
  else
    fail "boards/$board/positions.dtsi — expected $expected, got $count"
  fi
}

check_positions go60    60
check_positions glove80 80
check_positions slicemk 77

# ══════════════════════════════════════════════════════════════
section "4. Binding counts per layer"
# ══════════════════════════════════════════════════════════════

check_layer_bindings() {
  local board="$1" expected="$2"
  local bad=()
  for layer in "${LAYER_NAMES[@]}"; do
    local file="$REPO_ROOT/boards/$board/layers/$layer.dtsi"
    [[ -f "$file" ]] || continue
    local count
    count=$(count_bindings "$file")
    [[ "$count" -eq "$expected" ]] || bad+=("$layer(got $count)")
  done
  if [[ ${#bad[@]} -eq 0 ]]; then
    pass "boards/$board/layers/ — all layers have $expected bindings"
  else
    fail "boards/$board/layers/ — wrong counts: ${bad[*]} (expected $expected)"
  fi
}

check_layer_bindings go60    60
check_layer_bindings glove80 80
check_layer_bindings slicemk 77

# ══════════════════════════════════════════════════════════════
section "5. Combo DTS wrapper"
# ══════════════════════════════════════════════════════════════

# Board keymaps MUST have the wrapper
for board in go60 glove80 slicemk; do
  case "$board" in
    go60)    keymap="$REPO_ROOT/boards/go60/go60.keymap" ;;
    glove80) keymap="$REPO_ROOT/boards/glove80/glove80.keymap" ;;
    slicemk) keymap="$REPO_ROOT/boards/slicemk/slicemk.keymap" ;;
  esac
  if grep -q 'compatible = "zmk,combos"' "$keymap" 2>/dev/null; then
    pass "boards/$board keymap — / { combos { compatible = \"zmk,combos\"; }; } present"
  else
    fail "boards/$board keymap — missing combo DTS wrapper"
  fi
done

# Combo definition files must NOT have the wrapper (they are raw includes)
for f in combos_common combos_fkeys; do
  file="$REPO_ROOT/shared/combos/$f.dtsi"
  if grep -q 'compatible = "zmk,combos"' "$file" 2>/dev/null; then
    fail "shared/combos/$f.dtsi — must NOT contain wrapper (it's a raw include)"
  else
    pass "shared/combos/$f.dtsi — correctly has no wrapper"
  fi
done

# ══════════════════════════════════════════════════════════════
section "6. Shared includes in board keymaps"
# ══════════════════════════════════════════════════════════════

REQUIRED_INCLUDES=(
  "../../shared/layers.dtsi"
  "../../shared/homeRowMods/hrm_timings.dtsi"
  "../../shared/macros.dtsi"
  "../../shared/homeRowMods/hrm_macros.dtsi"
  "../../shared/behaviors.dtsi"
  "../../shared/modMorphs.dtsi"
  "../../shared/autoshift.dtsi"
  "../../shared/bluetooth.dtsi"
  "../../shared/magic.dtsi"
  "../../shared/homeRowMods/hrm_behaviors.dtsi"
)

for board in go60 glove80 slicemk; do
  case "$board" in
    go60)    keymap="$REPO_ROOT/boards/go60/go60.keymap" ;;
    glove80) keymap="$REPO_ROOT/boards/glove80/glove80.keymap" ;;
    slicemk) keymap="$REPO_ROOT/boards/slicemk/slicemk.keymap" ;;
  esac
  missing_inc=()
  for inc in "${REQUIRED_INCLUDES[@]}"; do
    grep -qF "#include \"$inc\"" "$keymap" 2>/dev/null || missing_inc+=("$(basename "$inc")")
  done
  if [[ ${#missing_inc[@]} -eq 0 ]]; then
    pass "boards/$board keymap — all 10 shared includes present"
  else
    fail "boards/$board keymap — missing includes: ${missing_inc[*]}"
  fi
done

# ══════════════════════════════════════════════════════════════
section "7. Position group defines"
# ══════════════════════════════════════════════════════════════

REQUIRED_GROUPS=(
  LEFT_HAND_KEYS
  RIGHT_HAND_KEYS
  THUMB_KEYS
  HRM_LEFT_TRIGGER_POSITIONS
  HRM_RIGHT_TRIGGER_POSITIONS
)

for board in go60 glove80 slicemk; do
  file="$REPO_ROOT/boards/$board/position_groups.dtsi"
  missing_groups=()
  for group in "${REQUIRED_GROUPS[@]}"; do
    grep -q "^#define $group" "$file" 2>/dev/null || missing_groups+=("$group")
  done
  if [[ ${#missing_groups[@]} -eq 0 ]]; then
    pass "boards/$board/position_groups.dtsi — all 5 groups defined"
  else
    fail "boards/$board/position_groups.dtsi — missing: ${missing_groups[*]}"
  fi
done

# ══════════════════════════════════════════════════════════════
section "8. Layer constants in shared/layers.dtsi"
# ══════════════════════════════════════════════════════════════

LAYER_CONSTS=(
  Base Typing Autoshift
  LeftPinky LeftRingy LeftMiddy LeftIndex
  RightPinky RightRingy RightMiddy RightIndex
  Cursor Keypad Symbol
  Mouse MouseSlow MouseFast MouseWarp
  Magic
)

layers_file="$REPO_ROOT/shared/layers.dtsi"
missing_consts=()
for lc in "${LAYER_CONSTS[@]}"; do
  grep -q "LAYER_${lc}" "$layers_file" 2>/dev/null || missing_consts+=("LAYER_${lc}")
done
if [[ ${#missing_consts[@]} -eq 0 ]]; then
  pass "shared/layers.dtsi — all 19 LAYER_* constants defined"
else
  fail "shared/layers.dtsi — missing: ${missing_consts[*]}"
fi

# ══════════════════════════════════════════════════════════════
section "9. SliceMK build config"
# ══════════════════════════════════════════════════════════════

build_yaml="$REPO_ROOT/build.yaml"
grep -q 'slicemk_ergodox_202109' "$build_yaml" 2>/dev/null \
  && pass "build.yaml — board: slicemk_ergodox_202109" \
  || fail "build.yaml — board slicemk_ergodox_202109 not found"

grep -q 'slicemk_ergodox_leftcentral' "$build_yaml" 2>/dev/null \
  && pass "build.yaml — shield: slicemk_ergodox_leftcentral" \
  || fail "build.yaml — shield slicemk_ergodox_leftcentral not found"

west_yml="$REPO_ROOT/config/west.yml"
grep -q 'slicemk' "$west_yml" 2>/dev/null \
  && pass "config/west.yml — slicemk remote declared" \
  || fail "config/west.yml — slicemk remote missing"

grep -q 'self:' "$west_yml" 2>/dev/null \
  && pass "config/west.yml — self: path present" \
  || fail "config/west.yml — self: path missing"

# ══════════════════════════════════════════════════════════════
section "10. GitHub Actions workflow"
# ══════════════════════════════════════════════════════════════

workflow="$REPO_ROOT/.github/workflows/build.yml"

grep -q 'build/go60.nix' "$workflow" 2>/dev/null \
  && pass ".github/workflows/build.yml — Go60 Nix build present" \
  || fail ".github/workflows/build.yml — Go60 Nix build missing"

grep -q 'build/glove80.nix' "$workflow" 2>/dev/null \
  && pass ".github/workflows/build.yml — Glove80 Nix build present" \
  || fail ".github/workflows/build.yml — Glove80 Nix build missing"

grep -q 'build-user-config.yml' "$workflow" 2>/dev/null \
  && pass ".github/workflows/build.yml — SliceMK reusable workflow present" \
  || fail ".github/workflows/build.yml — SliceMK reusable workflow missing"

grep -q 'moergo-glove80-zmk-dev' "$workflow" 2>/dev/null \
  && pass ".github/workflows/build.yml — MoErgo Cachix cache configured" \
  || warn ".github/workflows/build.yml — MoErgo Cachix cache not found (builds will be slow)"

# ══════════════════════════════════════════════════════════════
section "11. Stub status (informational)"
# ══════════════════════════════════════════════════════════════

for board in glove80 slicemk; do
  stub_count=0
  for layer in "${LAYER_NAMES[@]}"; do
    file="$REPO_ROOT/boards/$board/layers/$layer.dtsi"
    [[ -f "$file" ]] || continue
    non_trans=$(count_non_trans "$file")
    [[ "$non_trans" -eq 0 ]] && stub_count=$((stub_count + 1)) || true
  done
  if [[ "$stub_count" -eq 19 ]]; then
    warn "boards/$board/layers/ — all 19 layers are &trans stubs (need to be filled in)"
  elif [[ "$stub_count" -gt 0 ]]; then
    warn "boards/$board/layers/ — $stub_count of 19 layers still have all-&trans bindings"
  else
    pass "boards/$board/layers/ — all layers have real bindings"
  fi
done

# ══════════════════════════════════════════════════════════════
printf "\n${BOLD}══════════════════════════════════════════════${NC}\n"
printf "  ${GREEN}PASS: %-4d${NC}  ${RED}FAIL: %-4d${NC}  ${YELLOW}WARN: %-4d${NC}\n" \
       "$PASS" "$FAIL" "$WARN"
printf "${BOLD}══════════════════════════════════════════════${NC}\n\n"

[[ "$FAIL" -eq 0 ]] && exit 0 || exit 1
