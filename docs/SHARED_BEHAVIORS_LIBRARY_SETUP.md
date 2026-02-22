# Shared Behaviors & Macros — How They Work

All shared ZMK behaviors, macros, mod-morphs, and HRM configs live in the `shared/` directory at the root of this repo. Every board keymap includes them via relative paths. There is no separate external module — everything is self-contained.

---

## File map

| File | What it contains |
|---|---|
| `shared/layers.dtsi` | `LAYER_*` index `#define`s (0–18), shared across all boards |
| `shared/global_timings.dtsi` | Tapping-term and prior-idle `#define`s (tuned once, used everywhere) |
| `shared/macros.dtsi` | All ZMK macros: auto-pairs, tab switcher, drag lock, HRM hold/tap macros |
| `shared/behaviors.dtsi` | Non-positional hold-tap behaviors: `num_ht`, `bspc_word`, `thumb_v2_TKZ`, arrow taps, `tab_hyper`, `numpad_td`, `magic` |
| `shared/modMorphs.dtsi` | Mod-morph behaviors: `gresc`, `n9_paren`, `comma_angle`, `dqt_pair`, `upDownArrows` |
| `shared/autoshift.dtsi` | Autoshift behavior chain: `AS_HT`, `AS_Shifted`, `AS_v1` |
| `shared/bluetooth.dtsi` | Bluetooth profile switching behaviors and macros |
| `shared/magic.dtsi` | Magic layer behaviors (RGB status, system keys) — excluded from SliceMK |
| `shared/homeRowMods/hrm_macros.dtsi` | Per-finger hold and tap macros (referenced by `hrm_behaviors.dtsi`) |
| `shared/homeRowMods/hrm_behaviors.dtsi` | HRM hold-tap behaviors; uses `HRM_*_TRIGGER_POSITIONS` from each board's `position_groups.dtsi` |
| `shared/combos/combos_common.dtsi` | Raw combo nodes (no DTS wrapper) — works on all boards via logical position names |
| `shared/combos/combos_fkeys.dtsi` | F-key vertical combos |

---

## How a board keymap includes shared files

Each board's keymap (`boards/<board>/<board>.keymap`) includes shared files using relative paths:

```c
// Board-specific (must come before shared behaviors)
#include "positions.dtsi"           // POS_* physical → logical mapping
#include "position_groups.dtsi"     // HRM_LEFT/RIGHT_TRIGGER_POSITIONS
#include "../../shared/layers.dtsi"
#include "../../shared/global_timings.dtsi"
#include "board_meta.dtsi"          // Board-specific hardware (trackpad, RGB, etc.)

// Inside / { behaviors { }; }:
#include "../../shared/macros.dtsi"
#include "../../shared/homeRowMods/hrm_macros.dtsi"
#include "../../shared/behaviors.dtsi"
#include "../../shared/modMorphs.dtsi"
#include "../../shared/autoshift.dtsi"
#include "../../shared/bluetooth.dtsi"
#include "../../shared/magic.dtsi"            // Go60 + Glove80 only
#include "../../shared/homeRowMods/hrm_behaviors.dtsi"

// Inside / { keymap { }; }:
#include "layers/base.dtsi"
#include "layers/typing.dtsi"
// ... all 19 layers

// After keymap block:
#include "../../shared/combos/combos_common.dtsi"
#include "../../shared/combos/combos_fkeys.dtsi"
```

### Include order rules

The ordering above is not arbitrary:

1. `positions.dtsi` and `position_groups.dtsi` must come first — `HRM_*_TRIGGER_POSITIONS` must be defined before `hrm_behaviors.dtsi` is processed.
2. `layers.dtsi` and `global_timings.dtsi` must come before `board_meta.dtsi` — `board_meta.dtsi` uses `LAYER_*` constants and timing defines in tap-dance configs.
3. `hrm_macros.dtsi` must come before `hrm_behaviors.dtsi` — behaviors reference macros defined in the macros file.
4. Combo includes go outside the `/ { keymap { }; }` block — they wrap into their own `/ { combos { }; }` block inside each board keymap.

---

## HRM positional behaviors

The HRM behaviors in `hrm_behaviors.dtsi` use `hold-trigger-key-positions` for bilateral activation. This requires knowing which physical keys are on each hand — and that differs per board.

Each board's `position_groups.dtsi` defines:

```c
#define LEFT_HAND_KEYS   POS_LH_C6R1 POS_LH_C5R1 ...
#define RIGHT_HAND_KEYS  POS_RH_C1R1 POS_RH_C2R1 ...
#define THUMB_KEYS       POS_LH_T1 POS_LH_T2 POS_LH_T3 POS_RH_T1 ...

#define HRM_LEFT_TRIGGER_POSITIONS   RIGHT_HAND_KEYS THUMB_KEYS
#define HRM_RIGHT_TRIGGER_POSITIONS  LEFT_HAND_KEYS  THUMB_KEYS
```

`hrm_behaviors.dtsi` references these macros, so the same behavior file produces the correct trigger positions for each board at compile time.

---

## Adding or modifying a shared behavior

1. Edit the relevant file in `shared/` (see table above).
2. All three boards automatically pick up the change — no per-board edits needed for shared behaviors.
3. Run `./scripts/validation.sh` to catch any undefined `&label` references before committing.

---

## Adding a board-specific behavior

If a behavior should only exist on one board (e.g., a trackpad gesture only on Go60), define it in that board's `board_meta.dtsi`. Do not add it to the shared files.

---

## SliceMK exclusions

The `slicemk/zmk` fork does not support `RGB_STATUS`. Therefore:

- `shared/magic.dtsi` is **not** included in `boards/slicemk/slicemk.keymap`
- `boards/slicemk/layers/magic.dtsi` is **not** included in the SliceMK keymap block
- SliceMK uses `zmk/mouse.h` (old mouse API) instead of `zmk/pointing.h` (new API used by Go60/Glove80)

The validation script (`scripts/validation.sh`) enforces these exclusions.
