#!/usr/bin/env bash
# validation.sh — Validate the zmk-multi-keyboard-build repo structure
#
# Usage: ./scripts/validation.sh
# Exit code: 0 = all pass, 1 = one or more failures

set -u  # error on undefined variables; do NOT use -e or -o pipefail —
        # grep returning 1 (no match) must not abort the script

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
  # grep may return 1 (no match) — that's fine, wc -l handles empty input → 0
  perl -0777 -pe 's|/\*.*?\*/||gs' "$file" \
    | awk '/bindings = </{f=1;next} f && />;/{f=0;next} f{print}' \
    | { grep -oE '&[A-Za-z][A-Za-z0-9_]*' || true; } \
    | wc -l \
    | tr -d ' '
}

# Count non-&trans binding tokens in a layer file
count_non_trans() {
  local file="$1"
  perl -0777 -pe 's|/\*.*?\*/||gs' "$file" \
    | awk '/bindings = </{f=1;next} f && />;/{f=0;next} f{print}' \
    | { grep -oE '&[A-Za-z][A-Za-z0-9_]*' || true; } \
    | { grep -cv '^&trans$' || true; }
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
  shared/global_timings.dtsi
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

# Layer files actually included in each board's keymap
# SliceMK excludes magic (RGB_STATUS unsupported) → 18; others → 19
for board in go60 glove80 slicemk; do
  case "$board" in
    go60)    keymap="$REPO_ROOT/boards/go60/go60.keymap";       expected_layers=19 ;;
    glove80) keymap="$REPO_ROOT/boards/glove80/glove80.keymap"; expected_layers=19 ;;
    slicemk) keymap="$REPO_ROOT/boards/slicemk/slicemk.keymap"; expected_layers=18 ;;
  esac
  actual=$(grep -c '"layers/' "$keymap" 2>/dev/null || echo 0)
  if [[ "$actual" -eq "$expected_layers" ]]; then
    pass "boards/$board keymap — $actual layer includes in keymap (expected $expected_layers)"
  else
    fail "boards/$board keymap — $actual layer includes in keymap, expected $expected_layers"
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
  "../../shared/global_timings.dtsi"
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
    # magic is intentionally excluded from SliceMK (RGB_STATUS unsupported in slicemk/zmk fork)
    [[ "$board" == "slicemk" && "$inc" == *"magic.dtsi"* ]] && continue
    grep -qF "#include \"$inc\"" "$keymap" 2>/dev/null || missing_inc+=("$(basename "$inc")")
  done
  expected_count=$([[ "$board" == "slicemk" ]] && echo 9 || echo 10)
  if [[ ${#missing_inc[@]} -eq 0 ]]; then
    pass "boards/$board keymap — all $expected_count shared includes present"
  else
    fail "boards/$board keymap — missing includes: ${missing_inc[*]}"
  fi
done

# SliceMK-specific exclusions — these must NOT appear (incompatible with slicemk/zmk fork)
slicemk_km="$REPO_ROOT/boards/slicemk/slicemk.keymap"
grep -qF 'zmk/rgb.h' "$slicemk_km" 2>/dev/null \
  && fail "boards/slicemk keymap — rgb.h must NOT be included (RGB_STATUS unsupported in slicemk/zmk fork)" \
  || pass "boards/slicemk keymap — rgb.h correctly excluded"
grep -qF 'shared/magic.dtsi' "$slicemk_km" 2>/dev/null \
  && fail "boards/slicemk keymap — shared/magic.dtsi must NOT be included (RGB_STATUS unsupported in slicemk/zmk fork)" \
  || pass "boards/slicemk keymap — shared/magic.dtsi correctly excluded"
grep -qF 'layers/magic.dtsi' "$slicemk_km" 2>/dev/null \
  && fail "boards/slicemk keymap — layers/magic.dtsi must NOT be included in keymap" \
  || pass "boards/slicemk keymap — layers/magic.dtsi correctly excluded from keymap"

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
grep -q 'slicemk_ergodox_202207_green_left' "$build_yaml" 2>/dev/null \
  && pass "build.yaml — board: slicemk_ergodox_202207_green_left" \
  || fail "build.yaml — board slicemk_ergodox_202207_green_left not found"

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
section "12. Include ordering: layers.dtsi + global_timings.dtsi before board_meta.dtsi"
# ══════════════════════════════════════════════════════════════
# board_meta.dtsi uses LAYER_* macros (from shared/layers.dtsi) and
# timing constants like TD_TAPPING_TERM (from global_timings.dtsi) via
# ZMK_TD_LAYER. Both must be #included before board_meta.dtsi.

for board in go60 glove80 slicemk; do
  case "$board" in
    go60)    keymap="$REPO_ROOT/boards/go60/go60.keymap" ;;
    glove80) keymap="$REPO_ROOT/boards/glove80/glove80.keymap" ;;
    slicemk) keymap="$REPO_ROOT/boards/slicemk/slicemk.keymap" ;;
  esac
  [[ -f "$keymap" ]] || continue

  layers_ln=$(grep -n 'layers\.dtsi' "$keymap" 2>/dev/null | head -1 | cut -d: -f1 || true)
  timings_ln=$(grep -n 'global_timings\.dtsi' "$keymap" 2>/dev/null | head -1 | cut -d: -f1 || true)
  meta_ln=$(grep -n 'board_meta\.dtsi' "$keymap" 2>/dev/null | head -1 | cut -d: -f1 || true)

  if [[ -z "$layers_ln" || -z "$meta_ln" ]]; then
    warn "boards/$board keymap — could not find layers.dtsi or board_meta.dtsi include"
  elif [[ "$layers_ln" -lt "$meta_ln" ]]; then
    pass "boards/$board keymap — layers.dtsi (line $layers_ln) before board_meta.dtsi (line $meta_ln)"
  else
    fail "boards/$board keymap — layers.dtsi (line $layers_ln) AFTER board_meta.dtsi (line $meta_ln); LAYER_* macros will be undefined"
  fi

  if [[ -z "$timings_ln" || -z "$meta_ln" ]]; then
    warn "boards/$board keymap — could not find global_timings.dtsi or board_meta.dtsi include"
  elif [[ "$timings_ln" -lt "$meta_ln" ]]; then
    pass "boards/$board keymap — global_timings.dtsi (line $timings_ln) before board_meta.dtsi (line $meta_ln)"
  else
    fail "boards/$board keymap — global_timings.dtsi (line $timings_ln) AFTER board_meta.dtsi (line $meta_ln); TD_TAPPING_TERM will be undefined in ZMK_TD_LAYER"
  fi
done

# ══════════════════════════════════════════════════════════════
section "13. Behavior/macro includes inside / { behaviors { } } block"
# ══════════════════════════════════════════════════════════════
# DTS bare node definitions (label: node { }) cannot appear at the
# top level of a file — they must be inside a / { ... }; block.
# We verify by checking that:
#   (a) a "behaviors {" block exists in the keymap, and
#   (b) each behavior/macro include line is indented (not at column 0).

BEHAVIOR_INCLUDES=(
  "shared/macros.dtsi"
  "shared/homeRowMods/hrm_macros.dtsi"
  "shared/behaviors.dtsi"
  "shared/modMorphs.dtsi"
  "shared/autoshift.dtsi"
  "shared/bluetooth.dtsi"
  "shared/magic.dtsi"
  "shared/homeRowMods/hrm_behaviors.dtsi"
)

for board in go60 glove80 slicemk; do
  case "$board" in
    go60)    keymap="$REPO_ROOT/boards/go60/go60.keymap" ;;
    glove80) keymap="$REPO_ROOT/boards/glove80/glove80.keymap" ;;
    slicemk) keymap="$REPO_ROOT/boards/slicemk/slicemk.keymap" ;;
  esac
  [[ -f "$keymap" ]] || continue

  # (a) behaviors { block must exist
  if ! grep -q 'behaviors\s*{' "$keymap" 2>/dev/null; then
    fail "boards/$board keymap — no 'behaviors {' block found; behavior/macro includes must be wrapped"
    continue
  fi

  # (b) each behavior/macro include must be indented (inside a block)
  bare=()
  for inc in "${BEHAVIOR_INCLUDES[@]}"; do
    basename_inc=$(basename "$inc")
    while IFS= read -r matchline; do
      # Line is bare (top-level) if it starts with #include (no leading whitespace)
      if [[ "$matchline" =~ ^'#include' ]]; then
        bare+=("$basename_inc")
      fi
    done < <(grep "\"$basename_inc\"" "$keymap" 2>/dev/null || true)
  done

  if [[ ${#bare[@]} -eq 0 ]]; then
    pass "boards/$board keymap — all behavior/macro includes are inside a / { } block"
  else
    fail "boards/$board keymap — bare (top-level) includes: ${bare[*]}  ← must be inside / { behaviors { } }"
  fi
done

# ══════════════════════════════════════════════════════════════
section "14. Duplicate DTS labels in shared dtsi files"
# ══════════════════════════════════════════════════════════════
# A label defined twice in the same file (e.g. bt_0: bt_0 { } appearing
# twice) is a DTS error. Detect it with perl to handle multi-line files.

while IFS= read -r -d '' dtsi; do
  dupes=$(perl -ne 'print "$1\n" if /^\s*(\w+)\s*:\s*\w+\s*\{/' "$dtsi" \
          | sort | uniq -d)
  rel="${dtsi#$REPO_ROOT/}"
  if [[ -n "$dupes" ]]; then
    fail "$rel — duplicate DTS labels: $(echo "$dupes" | tr '\n' ' ')"
  else
    pass "$rel — no duplicate labels"
  fi
done < <(find "$REPO_ROOT/shared" -name '*.dtsi' -print0)

# ══════════════════════════════════════════════════════════════
section "15. Layer index continuity in shared/layers.dtsi"
# ══════════════════════════════════════════════════════════════
# Active (non-commented) LAYER_* defines must be contiguous from 0.

layers_file="$REPO_ROOT/shared/layers.dtsi"
if [[ -f "$layers_file" ]]; then
  expected=0
  gap_found=false
  count=0
  while IFS= read -r idx; do
    count=$((count + 1))
    if [[ "$idx" -ne "$expected" ]]; then
      fail "shared/layers.dtsi — gap in layer indices: expected $expected, got $idx (indices must be contiguous from 0)"
      gap_found=true
      break
    fi
    expected=$((expected + 1))
  done < <(grep -E '^#define LAYER_[A-Z]' "$layers_file" 2>/dev/null | grep -oE '[0-9]+$' | sort -n | uniq || true)
  [[ "$gap_found" == false ]] && pass "shared/layers.dtsi — $count layer indices are contiguous (0–$((expected - 1)))"
fi

# ══════════════════════════════════════════════════════════════
section "16. Auto-pair macros defined in shared/macros.dtsi"
# ══════════════════════════════════════════════════════════════
# modMorphs.dtsi references &pair_paren, &pair_angle, &pair_dquote.
# These macros must be defined in shared/macros.dtsi or the DTS link
# step will fail with "undefined node label".

macros_file="$REPO_ROOT/shared/macros.dtsi"
for label in pair_paren pair_angle pair_dquote pair_bracket pair_brace; do
  if grep -q "^${label}:" "$macros_file" 2>/dev/null; then
    pass "shared/macros.dtsi — $label defined"
  else
    fail "shared/macros.dtsi — $label MISSING (referenced by modMorphs.dtsi)"
  fi
done

# rgb_ug_status_macro must live in shared/magic.dtsi (not macros.dtsi) so that
# boards which exclude magic.dtsi (SliceMK) don't pull in the RGB_STATUS reference.
if grep -q 'rgb_ug_status_macro' "$macros_file" 2>/dev/null; then
  fail "shared/macros.dtsi — rgb_ug_status_macro must NOT be here (must stay in shared/magic.dtsi so SliceMK can exclude it)"
else
  pass "shared/macros.dtsi — rgb_ug_status_macro correctly absent"
fi
if grep -q 'rgb_ug_status_macro' "$REPO_ROOT/shared/magic.dtsi" 2>/dev/null; then
  pass "shared/magic.dtsi — rgb_ug_status_macro defined here (correct location)"
else
  fail "shared/magic.dtsi — rgb_ug_status_macro MISSING (must be defined here, not in macros.dtsi)"
fi

# ══════════════════════════════════════════════════════════════
section "17. pointing.h and mkp_drag_lock in all boards"
# ══════════════════════════════════════════════════════════════
# All boards use &mkp for mouse button actions (even without a physical
# trackpad). pointing.h must be included everywhere so LCLK etc. resolve,
# and mkp_drag_lock must live in shared/macros.dtsi (not board-specific).

# mkp_drag_lock must be in shared/macros.dtsi
if grep -q 'mkp_drag_lock' "$REPO_ROOT/shared/macros.dtsi" 2>/dev/null; then
  pass "shared/macros.dtsi — mkp_drag_lock present"
else
  fail "shared/macros.dtsi — mkp_drag_lock MISSING"
fi

# Go60 and Glove80 use moergo-sc/zmk (new pointing API) → must have pointing.h
for board in go60 glove80; do
  case "$board" in
    go60)    keymap="$REPO_ROOT/boards/go60/go60.keymap" ;;
    glove80) keymap="$REPO_ROOT/boards/glove80/glove80.keymap" ;;
  esac
  if grep -q 'zmk/pointing\.h' "$keymap" 2>/dev/null; then
    pass "boards/$board keymap — pointing.h included"
  else
    fail "boards/$board keymap — pointing.h MISSING (required for &mkp LCLK etc.)"
  fi
done

# SliceMK uses slicemk/zmk (old mouse API) → must have mouse.h, not pointing.h
slicemk_keymap="$REPO_ROOT/boards/slicemk/slicemk.keymap"
if grep -q 'zmk/mouse\.h' "$slicemk_keymap" 2>/dev/null; then
  pass "boards/slicemk keymap — mouse.h included (slicemk/zmk old API)"
else
  fail "boards/slicemk keymap — mouse.h MISSING (required for &mkp on slicemk/zmk fork)"
fi
if grep -q 'zmk/pointing\.h' "$slicemk_keymap" 2>/dev/null; then
  warn "boards/slicemk keymap — includes pointing.h; verify slicemk/zmk fork has this header"
fi

# ══════════════════════════════════════════════════════════════
section "18. All &label references in layers/combos resolve"
# ══════════════════════════════════════════════════════════════
# For each board, every &label used in keymap layers or combo bindings
# must be either a ZMK built-in behavior or defined somewhere in
# shared/board dtsi files. Catches "undefined node label" DTS build
# errors before they reach the compiler.

# ZMK built-in behavior labels — no user definition required
ZMK_BUILTINS=(
  kp mo to lt mt none trans sk sl
  mkp mmv msc
  bt rgb_ug out
  bootloader reset sys_reset
  key_repeat caps_word
  ext_power
  macro_tap macro_press macro_release macro_pause_for_release
  macro_param_1to1 macro_param_1to2 macro_param_2to1 macro_param_2to2
)

for board in go60 glove80 slicemk; do
  board_dir="$REPO_ROOT/boards/$board"

  # Collect all user-defined labels from shared + board dtsi (excluding layer files).
  # Handles: "label: node {" and ZMK helper macros ZMK_TD_LAYER/ZMK_BEHAVIOR/ZMK_TAP_DANCE.
  defined=""
  while IFS= read -r f; do
    defined+=$(perl -ne '
      print "$1\n" if /^\s*(\w+)\s*:\s*\w+\s*\{/;
      print "$1\n" if /ZMK_TD_LAYER\s*\(\s*(\w+)/;
      print "$1\n" if /ZMK_BEHAVIOR\s*\(\s*(\w+)/;
      print "$1\n" if /ZMK_TAP_DANCE\s*\(\s*(\w+)/;
    ' "$f" 2>/dev/null)$'\n'
  done < <(find "$REPO_ROOT/shared" "$board_dir" -name '*.dtsi' \
             ! -path '*/layers/*' 2>/dev/null)

  # Collect &label references from:
  #   - board layer files (keymap bindings)
  #   - shared combo files (combo bindings)
  #   - shared behavior/macro files (e.g. magic.dtsi referencing rgb_ug_status_macro)
  # This catches undefined references in both layer bindings AND shared behavior definitions.
  refs=""
  while IFS= read -r f; do
    # Strip block comments, line comments, and quoted strings before extracting
    # &label phandle references — avoids false positives from comment text and
    # ZMK's legacy label = "&FOO" metadata properties.
    refs+=$(perl -0777 -ne '
      s|/\*.*?\*/||gs;
      s|//[^\n]*||g;
      s|"[^"]*"||g;
      print "$1\n" while /&([A-Za-z][A-Za-z0-9_]*)/g;
    ' "$f" 2>/dev/null)$'\n'
  done < <(find "$board_dir/layers" "$REPO_ROOT/shared/combos" "$REPO_ROOT/shared" \
             -name '*.dtsi' 2>/dev/null)

  # Report any reference that is neither a built-in nor user-defined
  undefined=()
  while IFS= read -r ref; do
    [[ -z "$ref" ]] && continue
    # Skip built-ins
    is_bi=false
    for b in "${ZMK_BUILTINS[@]}"; do
      [[ "$ref" == "$b" ]] && { is_bi=true; break; }
    done
    [[ "$is_bi" == true ]] && continue
    # Skip if user-defined
    echo "$defined" | grep -qx "$ref" || undefined+=("&$ref")
  done < <(echo "$refs" | sort -u)

  if [[ ${#undefined[@]} -eq 0 ]]; then
    pass "boards/$board — all &label references in layers/combos resolve"
  else
    fail "boards/$board — undefined &labels: ${undefined[*]}"
  fi
done

# ══════════════════════════════════════════════════════════════
section "19. hold-tap behaviors must have #binding-cells = <2>"
# ══════════════════════════════════════════════════════════════
# ZMK's zmk,behavior-hold-tap YAML schema declares #binding-cells as a
# const = 2. Any other value causes a devicetree error at build time.

HOLD_TAP_FILES=(
  shared/behaviors.dtsi
  shared/homeRowMods/hrm_behaviors.dtsi
)

for rel in "${HOLD_TAP_FILES[@]}"; do
  f="$REPO_ROOT/$rel"
  [[ -f "$f" ]] || continue
  bad_nodes=$(perl -0777 -e '
    my $text = do { local $/; <> };
    my @bad;
    while ($text =~ /(\w+)\s*:\s*\w+\s*\{([^{}]+)\}/gs) {
      my ($label, $body) = ($1, $2);
      next unless $body =~ /compatible\s*=\s*"zmk,behavior-hold-tap"/;
      push @bad, $label unless $body =~ /#binding-cells\s*=\s*<2>/;
    }
    print join(" ", @bad), "\n";
  ' "$f")
  bad_nodes=$(echo "$bad_nodes" | xargs)
  if [[ -z "$bad_nodes" ]]; then
    pass "$rel — all hold-tap behaviors have #binding-cells = <2>"
  else
    fail "$rel — hold-tap behaviors with wrong #binding-cells (must be <2>): $bad_nodes"
  fi
done

# ══════════════════════════════════════════════════════════════
section "20. Timing constants in behavior files are defined in global_timings.dtsi"
# ══════════════════════════════════════════════════════════════
# DTS numeric properties (tapping-term-ms, quick-tap-ms, etc.) that use
# a bare UPPER_CASE identifier must resolve via the C preprocessor.
# An undefined constant causes: "parse error: expected number or parenthesized
# expression" at build time. This test catches typos like HRM_INDEX_QUICK_TAP
# (which should be HRM_QUICK_TAP) before they reach the compiler.

timings_file="$REPO_ROOT/shared/global_timings.dtsi"
BEHAVIOR_TIMING_FILES=(
  shared/behaviors.dtsi
  shared/homeRowMods/hrm_behaviors.dtsi
  shared/modMorphs.dtsi
  shared/autoshift.dtsi
)

if [[ ! -f "$timings_file" ]]; then
  fail "shared/global_timings.dtsi — not found (cannot validate timing constants)"
else
  defined_timings=$(grep -oE '^#define [A-Z][A-Z0-9_]+' "$timings_file" | awk '{print $2}' | tr '\n' ' ')

  for rel in "${BEHAVIOR_TIMING_FILES[@]}"; do
    f="$REPO_ROOT/$rel"
    [[ -f "$f" ]] || continue

    undef=()
    while IFS= read -r const; do
      [[ -z "$const" ]] && continue
      if ! echo " $defined_timings " | grep -q " $const "; then
        undef+=("$const")
      fi
    done < <(perl -ne '
      if (/(?:tapping-term-ms|quick-tap-ms|require-prior-idle-ms|timeout-ms)\s*=\s*<([^>]+)>/) {
        my $val = $1;
        print "$1\n" while $val =~ /([A-Z][A-Z0-9_]{3,})/g;
      }
    ' "$f" | sort -u)

    if [[ ${#undef[@]} -eq 0 ]]; then
      pass "$rel — all timing constants defined in global_timings.dtsi"
    else
      fail "$rel — timing constants NOT in global_timings.dtsi: ${undef[*]}"
    fi
  done
fi

# ══════════════════════════════════════════════════════════════
printf "\n${BOLD}══════════════════════════════════════════════${NC}\n"
printf "  ${GREEN}PASS: %-4d${NC}  ${RED}FAIL: %-4d${NC}  ${YELLOW}WARN: %-4d${NC}\n" \
       "$PASS" "$FAIL" "$WARN"
printf "${BOLD}══════════════════════════════════════════════${NC}\n\n"

[[ "$FAIL" -eq 0 ]] && exit 0 || exit 1
