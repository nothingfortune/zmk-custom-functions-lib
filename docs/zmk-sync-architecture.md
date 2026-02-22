# ZMK Multi-Keyboard Sync Architecture

## Goal

Maintain a single central repo that drives the keymaps for Go60, Glove80, and SliceMK boards. Update behaviors, macros, layers, and HRM config in one place; per-board keymaps pull from the shared library and only define what's physically unique to them.

---

## Repo Structure

```
zmk-keymap-central/
│
├── shared/                          # THE CORE — board-agnostic
│   ├── layers.dtsi                  # Layer number defines (universal)
│   ├── macros.dtsi                  # All macros (auto-pair, tab switch, drag lock, etc.)
│   ├── behaviors.dtsi               # Non-positional behaviors (num_ht, bspc_word, thumb_v2, etc.)
│   ├── modMorphs.dtsi               # gresc, n9_paren, comma_angle, dqt_pair, upDownArrows
│   ├── autoshift.dtsi               # AS_HT, AS_Shifted, AS_v1 behavior chain
│   ├── homeRowMods/
│   │   ├── hrm_macros.dtsi          # Hold/tap macros (per-finger _hold and _tap macros)
│   │   ├── hrm_behaviors.dtsi       # HRM hold-tap behaviors (uses position group macros)
│   │   └── global_timings.dtsi         # Central timing values as #defines
│   ├── combos/
│   │   ├── combos_common.dtsi       # Combos that work on all boards (use logical positions)
│   │   └── combos_fkeys.dtsi        # F-key vertical combos (shareable if position names match)
│   └── capsword.dtsi                # Caps word config
│
├── boards/                          # BOARD-SPECIFIC — physical reality
│   ├── go60/
│   │   ├── positions.dtsi           # POS_* defines mapping logical names → physical numbers
│   │   ├── position_groups.dtsi     # LEFT_HAND_KEYS, RIGHT_HAND_KEYS, THUMB_KEYS, etc.
│   │   ├── board_meta.dtsi          # KB_TYPE, EDITOR_HOST_OS, board-specific #ifdefs
│   │   ├── input_processors.dtsi    # Cirque trackpad config (Go60-only)
│   │   ├── layers/
│   │   │   ├── base.dtsi            # Base layer bindings (the physical grid)
│   │   │   ├── typing.dtsi          # Typing layer overrides
│   │   │   ├── autoshift.dtsi       # Autoshift layer bindings
│   │   │   ├── cursor.dtsi          # Cursor/nav layer bindings
│   │   │   ├── symbol.dtsi          # Symbol layer bindings
│   │   │   ├── keypad.dtsi          # Numpad layer bindings
│   │   │   ├── mouse.dtsi           # Mouse + MouseSlow/Fast/Warp layers
│   │   │   ├── hrm_fingers.dtsi     # Per-finger HRM layers (LeftPinky..RightIndex)
│   │   │   └── magic.dtsi           # Magic/system layer
│   │   └── go60.keymap              # Thin shell: includes + keymap wrapper only
│   │
│   ├── glove80/
│   │   ├── positions.dtsi           # Glove80 physical position → logical name mapping
│   │   ├── position_groups.dtsi     # Glove80 hand/thumb groupings
│   │   ├── board_meta.dtsi
│   │   ├── layers/
│   │   │   ├── base.dtsi            # Glove80 base (same core, extra outer columns)
│   │   │   ├── ...                  # Same layer files, adapted to 80-key grid
│   │   │   └── extra_keys.dtsi      # Bindings for keys Go60 doesn't have
│   │   └── glove80.keymap
│   │
│   └── slicemk/
│       ├── positions.dtsi
│       ├── position_groups.dtsi
│       ├── board_meta.dtsi
│       ├── layers/
│       │   └── ...
│       └── slicemk.keymap
│
├── scripts/
│   ├── validate.sh                  # Lint/verify all boards compile
│   └── diff_layers.sh              # Show functional diff between boards
│
└── README.md
```

---

## The Abstraction Layers

### Layer 1: Logical Position Names (the key contract)

Every board defines the same `POS_*` names pointing to its own physical position numbers. This is the **single most important abstraction** — it's what allows everything above it to be shared.

```c
// boards/go60/positions.dtsi
#define POS_LH_C5R3 25   // Left hand, column 5, row 3 → physical key 25

// boards/glove80/positions.dtsi
#define POS_LH_C5R3 37   // Same logical position → different physical key number

// boards/slicemk/positions.dtsi
#define POS_LH_C5R3 19   // Same logical position → different physical key number
```

Your naming convention (`LH/RH` + `C1-C6` + `R1-R5` + `T1-T3`) already works well. The only question is how to handle keys that exist on one board but not another.

**Convention for missing positions:**

```c
// boards/slicemk/positions.dtsi (if it has no C6 outer columns)
// #define POS_LH_C6R1 — intentionally undefined
// #define POS_LH_C6R2 — intentionally undefined
// Shared code that references C6 positions must be wrapped in:
//   #ifdef POS_LH_C6R1
//   ...
//   #endif
```

### Layer 2: Position Groups (for bilateral HRM)

These aggregate logical positions into groups. The HRM behaviors reference these.

```c
// boards/go60/position_groups.dtsi
#define LEFT_HAND_KEYS \
  POS_LH_C1R1 POS_LH_C2R1 POS_LH_C3R1 POS_LH_C4R1 POS_LH_C5R1 POS_LH_C6R1 \
  POS_LH_C1R2 POS_LH_C2R2 POS_LH_C3R2 POS_LH_C4R2 POS_LH_C5R2 POS_LH_C6R2 \
  ...

#define RIGHT_HAND_KEYS \
  ...

#define THUMB_KEYS \
  POS_LH_T1 POS_LH_T2 POS_LH_T3 \
  POS_RH_T1 POS_RH_T2 POS_RH_T3

// Composite groups used by HRM hold-trigger-key-positions
#define HRM_LEFT_TRIGGER_POSITIONS  RIGHT_HAND_KEYS THUMB_KEYS
#define HRM_RIGHT_TRIGGER_POSITIONS LEFT_HAND_KEYS THUMB_KEYS
```

The Glove80 version includes more positions (extra columns, extra thumb keys). The shared HRM behaviors don't care — they just reference `HRM_LEFT_TRIGGER_POSITIONS`.

### Layer 3: Shared Timings

Centralize all timing values so tuning is a one-file change:

```c
// shared/global_timings.dtsi

#define HRM_INDEX_TAPPING_TERM   190
#define HRM_MIDDY_TAPPING_TERM   210
#define HRM_RING_TAPPING_TERM    240
#define HRM_PINKY_TAPPING_TERM   260

#define HRM_INDEX_PRIOR_IDLE     100
#define HRM_MIDDY_PRIOR_IDLE     150
#define HRM_RING_PRIOR_IDLE      150
#define HRM_PINKY_PRIOR_IDLE     150

#define HRM_QUICK_TAP            300

#define THUMB_TAPPING_TERM       200
#define THUMB_QUICK_TAP          300

#define NUM_HT_TAPPING_TERM      170
#define NUM_HT_QUICK_TAP         175
#define NUM_HT_PRIOR_IDLE        125

#define AUTOSHIFT_TAPPING_TERM   190

#define BSPC_WORD_TAPPING_TERM   250
#define BSPC_WORD_PRIOR_IDLE     200

#define ARROW_TAPPING_TERM       250
#define ARROW_QUICK_TAP          200
#define ARROW_PRIOR_IDLE         150
```

### Layer 4: Shared Behaviors (non-positional)

These reference timings but not positions — fully portable:

```c
// shared/behaviors.dtsi
#include "global_timings.dtsi"

/ {
    behaviors {
        // Thumb layer access
        thumb_v2_TKZ: thumb_v2_TKZ {
            compatible = "zmk,behavior-hold-tap";
            #binding-cells = <2>;
            tapping-term-ms = <THUMB_TAPPING_TERM>;
            bindings = <&mo>, <&kp>;
            flavor = "balanced";
            quick-tap-ms = <THUMB_QUICK_TAP>;
        };

        // Number row hold-tap
        num_ht: num_hold_tap {
            compatible = "zmk,behavior-hold-tap";
            #binding-cells = <2>;
            flavor = "balanced";
            tapping-term-ms = <NUM_HT_TAPPING_TERM>;
            quick-tap-ms = <NUM_HT_QUICK_TAP>;
            require-prior-idle-ms = <NUM_HT_PRIOR_IDLE>;
            bindings = <&kp>, <&kp>;
        };

        // Backspace / delete word
        bspc_word: backspace_word {
            compatible = "zmk,behavior-hold-tap";
            #binding-cells = <2>;
            flavor = "balanced";
            tapping-term-ms = <BSPC_WORD_TAPPING_TERM>;
            quick-tap-ms = <0>;
            require-prior-idle-ms = <BSPC_WORD_PRIOR_IDLE>;
            bindings = <&kp>, <&kp>;
        };

        // Arrow word-jump hold-taps
        arrow_left: arrow_word_left { ... };
        arrow_right: arrow_word_right { ... };

        // Caps word
        cw: caps_word { ... };

        // Up/Down mod-morph
        upDownArrows: up_down_arrows { ... };

        // Tab/Hyper tap-dance
        tab_hyper: tab_hyper { ... };

        // Layer tap-dance
        numpad_td: numpad_td { ... };

        // Magic hold-tap
        magic: magic { ... };
    };
};
```

### Layer 5: Shared HRM Behaviors (positional — uses group macros)

This is where the magic happens. The behaviors reference `HRM_LEFT_TRIGGER_POSITIONS` / `HRM_RIGHT_TRIGGER_POSITIONS` which resolve differently per board:

```c
// shared/homeRowMods/hrm_behaviors.dtsi
// MUST be included AFTER the board's position_groups.dtsi

/ {
    behaviors {
        // Left index — primary bilateral
        HRM_left_index_v1B_TKZ: HRM_left_index_v1B_TKZ {
            compatible = "zmk,behavior-hold-tap";
            #binding-cells = <2>;
            tapping-term-ms = <HRM_INDEX_TAPPING_TERM>;
            bindings = <&HRM_left_index_hold_v1B_TKZ>, <&kp>;
            flavor = "tap-preferred";
            quick-tap-ms = <HRM_QUICK_TAP>;
            require-prior-idle-ms = <HRM_INDEX_PRIOR_IDLE>;
            hold-trigger-key-positions = <HRM_LEFT_TRIGGER_POSITIONS>;
            hold-trigger-on-release;
        };

        // Left index — cross-finger variants (middy, ring, pinky)
        HRM_left_index_middy_v1B_TKZ: HRM_left_index_middy_v1B_TKZ {
            compatible = "zmk,behavior-hold-tap";
            #binding-cells = <2>;
            tapping-term-ms = <HRM_INDEX_TAPPING_TERM>;
            bindings = <&kp>, <&HRM_left_index_tap_v1B_TKZ>;
            flavor = "tap-preferred";
            quick-tap-ms = <HRM_QUICK_TAP>;
            require-prior-idle-ms = <HRM_INDEX_PRIOR_IDLE>;
            hold-trigger-key-positions = <HRM_LEFT_TRIGGER_POSITIONS>;
            hold-trigger-on-release;
        };

        // ... same pattern for all 8 fingers × 4 cross-finger variants ...

        // Right pinky — primary bilateral (longest tapping term)
        HRM_right_pinky_v1B_TKZ: HRM_right_pinky_v1B_TKZ {
            compatible = "zmk,behavior-hold-tap";
            #binding-cells = <2>;
            tapping-term-ms = <HRM_PINKY_TAPPING_TERM>;
            bindings = <&HRM_right_pinky_hold_v1B_TKZ>, <&kp>;
            flavor = "tap-preferred";
            quick-tap-ms = <HRM_QUICK_TAP>;
            require-prior-idle-ms = <HRM_PINKY_PRIOR_IDLE>;
            hold-trigger-key-positions = <HRM_RIGHT_TRIGGER_POSITIONS>;
            hold-trigger-on-release;
        };
    };
};
```

### Layer 6: Shared Macros (fully portable)

These don't reference positions or physical layout at all:

```c
// shared/macros.dtsi

/ {
    macros {
        // Auto-pairs
        pair_paren: pair_parentheses { ... };
        pair_bracket: pair_brackets { ... };
        pair_brace: pair_braces { ... };
        pair_angle: pair_angle_brackets { ... };
        pair_dquote: pair_double_quotes { ... };

        // Navigation
        mac_tab_next: mac_tab_next { ... };
        mac_tab_prev: mac_tab_prev { ... };
        mac_mission_ctl: mac_mission_ctl { ... };
        mac_app_expose: mac_app_expose { ... };

        // Mouse
        mkp_drag_lock: mouse_drag_lock { ... };

        // Hyper
        hyper_key: hyper_key_macro { ... };

        // HRM per-finger hold/tap macros
        // (These reference specific letters like &kp F, &kp A etc.
        //  but that's fine — the letters are part of your QWERTY
        //  homerow contract, not physical positions)
        HRM_left_index_hold_v1B_TKZ: ... { ... };
        HRM_left_index_tap_v1B_TKZ: ... { ... };
        // ... all 8 fingers ...

        // Cursor layer macros
        cur_EXTEND_LINE_macos_v1_TKZ: ... { ... };
        cur_EXTEND_WORD_macos_v1_TKZ: ... { ... };
        cur_SELECT_LINE_macos_v1_TKZ: ... { ... };
        cur_SELECT_WORD_macos_v1_TKZ: ... { ... };
        cur_SELECT_NONE_v1_TKZ: ... { ... };

        // Symbol
        symb_dotdot_v1_TKZ: ... { ... };

        // Tab switcher
        mod_tab_v1_TKZ: ... { ... };
        mod_tab_chord_v2_TKZ: ... { ... };
    };
};
```

---

## What Each Board's .keymap Looks Like

After the refactor, a board keymap becomes a thin assembly file:

```c
// boards/go60/go60.keymap

#include <behaviors.dtsi>
#include <dt-bindings/zmk/outputs.h>
#include <dt-bindings/zmk/keys.h>
#include <dt-bindings/zmk/bt.h>
#include <dt-bindings/zmk/rgb.h>
#include <input/processors.dtsi>
#include <dt-bindings/zmk/input_transform.h>
#include <dt-bindings/zmk/pointing.h>

/* ===== Board-specific ===== */
#include "positions.dtsi"            // POS_* physical → logical mapping
#include "position_groups.dtsi"      // LEFT_HAND_KEYS, HRM_*_TRIGGER_POSITIONS
#include "board_meta.dtsi"           // KB_TYPE, HOST_OS
#include "input_processors.dtsi"     // Cirque trackpad config (Go60 only)

/* ===== Shared core ===== */
#include <zmk-keymap-central/shared/layers.dtsi>
#include <zmk-keymap-central/shared/macros.dtsi>
#include <zmk-keymap-central/shared/behaviors.dtsi>
#include <zmk-keymap-central/shared/modMorphs.dtsi>
#include <zmk-keymap-central/shared/autoshift.dtsi>
#include <zmk-keymap-central/shared/capsword.dtsi>
#include <zmk-keymap-central/shared/homeRowMods/hrm_macros.dtsi>
#include <zmk-keymap-central/shared/homeRowMods/hrm_behaviors.dtsi>

/* ===== Board-specific layers ===== */
/ {
    keymap {
        compatible = "zmk,keymap";
        #include "layers/base.dtsi"
        #include "layers/typing.dtsi"
        #include "layers/autoshift.dtsi"
        #include "layers/hrm_fingers.dtsi"
        #include "layers/cursor.dtsi"
        #include "layers/keypad.dtsi"
        #include "layers/symbol.dtsi"
        #include "layers/mouse.dtsi"
        #include "layers/magic.dtsi"
    };
};

/* ===== Board-specific combos ===== */
#include <zmk-keymap-central/shared/combos/combos_common.dtsi>
#include "combos_go60.dtsi"          // Board-specific combos if any

/* ===== Bluetooth (shared) ===== */
#include <zmk-keymap-central/shared/bluetooth.dtsi>
```

---

## Classification: What's Shared vs Board-Specific

### Fully Shareable (update once, all boards get it)

| Component                     | Why it's portable                                           |
|-------------------------------|-------------------------------------------------------------|
| All macros                    | Pure key sequences, no position refs                        |
| HRM hold/tap macros           | Reference letters (A,S,D,F,J,K,L,;) not positions           |
| HRM timing defines            | Just numbers                                                |
| Mod-morphs                    | Pure modifier logic                                         |
| Autoshift chain               | Pure behavior logic                                         |
| Caps word                     | Pure behavior config                                        |
| Layer number defines          | Shared convention                                           |
| Bluetooth macros              | Universal                                                   |
| Non-positional behaviors      | `num_ht`, `bspc_word`, `thumb_v2`, `arrow_*`, `tab_hyper`   |

### Shareable with Position Indirection (update once, resolves per-board)

| Component                     | What varies                                                            |
|-------------------------------|------------------------------------------------------------------------|
| HRM bilateral behaviors       | `hold-trigger-key-positions` → resolved via `HRM_*_TRIGGER_POSITIONS`  |
| F-key combos                  | `key-positions` → same logical names, different physical numbers       |
| Tab-switcher combo            | `key-positions`                                                        |

### Board-Specific (must maintain per-board)

| Component                     | Why it's unique                                 |
|-------------------------------|-------------------------------------------------|
| `positions.dtsi`              | Physical key matrix numbers differ              |
| `position_groups.dtsi`        | Different key counts per hand                   |
| Layer bindings (the grids)    | Different number of keys per row                |
| Input processor config        | Trackpad hardware differs (or absent)           |
| Extra-key bindings            | Glove80 has 20 keys Go60 doesn't                |
| Board meta                    | `KB_TYPE`, shield config                        |

---

## Handling the Layer Binding Grid Problem

The layer bindings are the hardest part to share because they're physical grids — each board has a different number of keys per row. Here are your options:

### Option A: Fully Per-Board Layer Files (Recommended)

Keep each board's layer bindings in their own files. The bindings *reference* shared behaviors (`&HRM_left_pinky_v1B_TKZ LGUI A`) which are defined in the shared library. So the behavior definitions are shared; only the physical grid layout is per-board.

**Pros:** Clean, no preprocessor gymnastics, easy to read.
**Cons:** When you add a new key to the symbol layer, you update 3 files.

### Option B: Macro-Based Row Templates

Define each row as a macro that expands differently per board:

```c
// shared abstraction
#define HOMEROW_LEFT(outer, pinky, ring, mid, idx, inner) \
    outer  pinky  ring  mid  idx  inner

// go60 base layer
HOMEROW_LEFT(&kp LSHFT, &HRM_left_pinky LGUI A, &HRM_left_ring LALT S, ...)
```

**Pros:** The "what goes on each key" is defined once.
**Cons:** Gets ugly fast with 12-column rows, hard to debug, ZMK's devicetree parser may not cooperate.

### Option C: Hybrid — Shared "Core Grid" + Board Padding

Define the inner 10 columns (which all three boards share) as a shared fragment. Each board wraps it with its outer columns:

```c
// shared/layers/base_core_homerow.dtsi (the 10 inner keys)
&HRM_left_pinky_v1B_TKZ LGUI A  \
&HRM_left_ring_v1B_TKZ LALT S   \
&HRM_left_middy_v1B_TKZ LCTRL D \
&HRM_left_index_v1B_TKZ LSHFT F \
&lt_v2_TKZ LAYER_Symbol G       \
&lt_v2_TKZ LAYER_Symbol H       \
&HRM_right_index_v1B_TKZ RSHFT J  \
&HRM_right_middy_v1B_TKZ RCTRL K  \
&HRM_right_ring_v1B_TKZ LALT L    \
&HRM_right_pinky_v1B_TKZ RGUI SEMI

// boards/go60/layers/base.dtsi
LAYER_Base {
    bindings = <
        // Row 1: number row
        &gresc  /* ...go60 specific grid... */
        // Row 3: homerow
        &kp LSHFT  #include <shared/layers/base_core_homerow.dtsi>  &dqt_pair
    >;
};
```

**Pros:** The functional "core" is truly shared. Outer keys are board-specific.
**Cons:** Fragile include paths, hard to visualize the full layer, ZMK's DTS parser may struggle with mid-binding includes.

### My Recommendation

**Go with Option A (fully per-board layer files) for now, with a documentation convention.** Here's why:

1. ZMK's devicetree format doesn't play nicely with macro-heavy row templates
2. You have 3 boards, not 30 — the maintenance cost is manageable
3. The behaviors, macros, and timings (where most iteration happens) ARE shared
4. Layer grids change rarely once stable
5. You can always add a script that diffs the "functional content" of layer files across boards to catch drift

Add a comment convention at the top of each layer file marking which shared behaviors it uses, so when you change a behavior name you can grep across boards:

```c
// SHARED REFS: HRM_left_pinky_v1B_TKZ, HRM_left_ring_v1B_TKZ, ...
// SHARED REFS: lt_v2_TKZ, thumb_v2_TKZ, num_ht, gresc, ...
```

---

## Migration Plan

### Phase 1: Extract and Centralize (don't change any functionality)

1. (done) Create the repo structure
2. (done) Extract all macros from `go60.keymap` → `shared/macros.dtsi`
3. (done) Extract all non-positional behaviors → `shared/behaviors.dtsi`
4. (done) Extract mod-morphs → `shared/modMorphs.dtsi`
5. (done) Extract HRM macros → `shared/homeRowMods/hrm_macros.dtsi`
6. (done) Extract timing defines → `shared/global_timings.dtsi`
7. (done) Replace hardcoded timings in HRM behaviors with timing defines
8. (done) Extract HRM behaviors → `shared/homeRowMods/hrm_behaviors.dtsi`
9. (done) Move `positions.dtsi` and `position_groups.dtsi` to `boards/go60/`
10. Verify the Go60 keymap compiles and works identically

### Phase 2: Add Glove80

1. Create `boards/glove80/positions.dtsi` with Glove80's physical position numbers
2. Create `boards/glove80/position_groups.dtsi` (will have more keys in each group)
3. Create Glove80 layer files referencing shared behaviors
4. Include the shared library
5. Verify functional parity with your current Glove80 keymap

### Phase 3: Add SliceMK

Same process. By now the shared library is proven.

### Phase 4: Add Tooling

1. `validate.sh` — compiles all boards, catches broken includes
2. `diff_layers.sh` — extracts the behavior references from each board's layer files and diffs them to surface unintentional divergence
3. Optional: a simple script that generates a markdown "cheat sheet" showing the logical layout for each board side by side

---

## Potential Gotchas

**ZMK module include paths.** Your shared library will need to be a ZMK module (like your current `zmk-custom-functions-lib`) so it gets pulled in at build time. The include path will be something like `<zmk-keymap-central/shared/macros.dtsi>`. Make sure `west.yml` or `build.yaml` references it.

**Layer order matters.** All boards must define layers in the same order with the same numbers. Your `shared/layers.dtsi` defines this centrally — any board that doesn't use a layer (e.g., SliceMK might not have mouse layers if it has no trackpad) should still define it as a transparent pass-through to keep numbering consistent.

**Conditional compilation for board-specific features.** Use `KB_TYPE` for this:

```c
#if KB_TYPE == KB_TYPE_GO_60
    #include "input_processors.dtsi"
#endif
```

**The HRM hold macros reference specific letters.** `HRM_left_index_hold_v1B_TKZ` hardcodes `&kp F` and `&mo LAYER_LeftIndex`. This ties you to QWERTY. If you ever want to support Colemak or another layout, these would need to be parameterized. Not a problem now, just worth knowing.

**TailorKey regeneration.** If you use TailorKey's layout editor to make changes, it will regenerate a monolithic keymap file. You'd need a process to diff what changed and port those changes into the appropriate shared/board-specific files. Alternatively, once the library is stable, you might stop using TailorKey's code gen and edit directly.

---

## The End State

After migration, changing your HRM timing is editing one line in `global_timings.dtsi`. Adding a new macro means editing `shared/macros.dtsi`. Changing your symbol layer means editing 3 layer files (one per board), but the behavior *references* in those files all point to the same shared definitions.

Your Go60 keymap goes from 2,225 lines to maybe 200 lines of includes + layer grids. The shared library holds the intelligence. Board files hold the geometry.
