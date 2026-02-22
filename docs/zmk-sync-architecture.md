# ZMK Multi-Keyboard Sync Architecture

## Goal

Maintain a single repo that drives the keymaps for Go60, Glove80, and SliceMK. Update behaviors, macros, layers, and HRM config in one place; per-board keymaps pull from the shared library and only define what's physically unique to each board. **Go60 is the source of truth for layer bindings.**

---

## Repo Structure

```
zmk-multi-keyboard-build/
│
├── shared/                          # Board-agnostic — update once, all boards get it
│   ├── layers.dtsi                  # LAYER_* index defines (0–18)
│   ├── macros.dtsi                  # All macros
│   ├── behaviors.dtsi               # Non-positional behaviors
│   ├── modMorphs.dtsi               # gresc, n9_paren, comma_angle, dqt_pair, upDownArrows
│   ├── autoshift.dtsi               # Autoshift behavior chain
│   ├── bluetooth.dtsi               # BT profile switching
│   ├── magic.dtsi                   # RGB status (excluded from SliceMK)
│   ├── global_timings.dtsi          # Central timing #defines
│   ├── homeRowMods/
│   │   ├── hrm_macros.dtsi          # Per-finger hold/tap macros
│   │   └── hrm_behaviors.dtsi       # HRM hold-tap behaviors (positional via group macros)
│   └── combos/
│       ├── combos_common.dtsi       # Raw combo nodes — all boards
│       └── combos_fkeys.dtsi        # F-key vertical combos
│
├── boards/                          # Board-specific — physical layout reality
│   ├── go60/                        # SOURCE OF TRUTH for layer bindings
│   │   ├── positions.dtsi           # POS_* → physical key number (60 keys)
│   │   ├── position_groups.dtsi     # LEFT/RIGHT_HAND_KEYS, HRM trigger groups
│   │   ├── board_meta.dtsi          # Trackpad, RGB, tap-dance config
│   │   ├── go60.keymap
│   │   ├── go60.conf
│   │   └── layers/                  # 19 layer files with real bindings
│   │
│   ├── glove80/                     # Synced from go60 via keymapsync.sh
│   │   ├── positions.dtsi           # POS_* → physical key number (80 keys)
│   │   ├── position_groups.dtsi
│   │   ├── board_meta.dtsi
│   │   ├── glove80.keymap
│   │   ├── glove80.conf
│   │   └── layers/                  # 19 layer files; shared positions filled by sync
│   │
│   └── slicemk/                     # Synced from go60 via keymapsync.sh
│       ├── positions.dtsi           # POS_* → physical key number (77 keys)
│       ├── position_groups.dtsi
│       ├── board_meta.dtsi
│       ├── slicemk.keymap
│       ├── slicemk.conf
│       └── layers/                  # 19 files; 18 active (no magic); shared positions synced
│
├── boards/translations/             # Index maps for keymapsync.sh
│   ├── go60_to_glove80.txt          # go60_idx → glove80_idx (60 pairs)
│   ├── go60_to_slicemk.txt          # go60_idx → slicemk_idx (60 pairs)
│   └── glove80_to_go60.txt          # glove80_idx → go60_idx (reverse, 60 pairs)
│
├── scripts/
│   ├── keymapsync.sh                # Propagates go60 layers → glove80 + slicemk
│   ├── diff_layers.sh               # Compares layer bindings across boards
│   └── validation.sh                # 18 structural checks; run by CI
│
├── config/                          # SliceMK west entry point
│   ├── west.yml
│   ├── slicemk_ergodox.keymap
│   └── slicemk_ergodox_leftcentral.conf
│
├── build/
│   ├── go60.nix
│   └── glove80.nix
│
├── build.yaml                       # SliceMK west build matrix
└── .github/workflows/build.yml      # CI: validate → build all 3 in parallel
```

---

## The Key Abstraction: Logical Position Names

Every board defines the same `POS_*` names pointing to its own physical position numbers. Shared behaviors, combos, and HRM configs reference logical names — the C preprocessor resolves them to the correct physical numbers at build time.

```c
// boards/go60/positions.dtsi
#define POS_LH_C5R3   25   // Left hand, col 5, row 3 → physical key 25

// boards/glove80/positions.dtsi
#define POS_LH_C5R3   35   // Same logical position → different physical key

// boards/slicemk/positions.dtsi
#define POS_LH_C5R3   30   // Same logical position → different physical key
```

60 positions are shared across all three boards (full cross-reference in `docs/positionmapping.md`). Each board additionally has positions that only exist on that board (Glove80 function row, SliceMK inner columns, extra thumb keys) — those remain board-specific.

---

## Layer Sync: go60 as Source of Truth

Layer bindings are per-board files because each board has a different number of keys per row. The sync workflow keeps them aligned for shared positions.

### Translation maps (`boards/translations/`)

Each `.txt` file lists `src_idx dst_idx` pairs — the flat binding array index in go60 mapped to the corresponding index in the target board. Derived directly from the `positions.dtsi` files via shared logical names.

```
# go60 -> glove80
0 10      # go60[0] (POS_LH_C6R1) → glove80[10]
1 11      # go60[1] (POS_LH_C5R1) → glove80[11]
...
54 69     # go60[54] (POS_LH_T1)  → glove80[69]
```

### `scripts/keymapsync.sh`

For each go60 layer file, the script:

1. Parses the `bindings = < ... >;` block into an array of complete binding groups. Each `&behavior [param1 [param2]]` is one element — correctly handling zero-param macros (`&gresc`, `&upDownArrows`) and multi-param behaviors (`&kp X`, `&HRM_left_pinky_v1B_TKZ LGUI A`) alike.
2. Parses the target board layer file the same way.
3. For each `src dst` pair in the translation map, replaces `target[dst]` with `go60[src]`.
4. Leaves all target-board-only positions completely untouched.
5. Rewrites only the bindings block in the target file, preserving surrounding DTS structure.

### Workflow

```sh
# 1. Edit a layer on go60
vim boards/go60/layers/base.dtsi

# 2. Propagate to glove80 + slicemk
./scripts/keymapsync.sh

# 3. Inspect results
./scripts/diff_layers.sh base go60 glove80

# 4. Edit any board-specific positions manually if needed
vim boards/glove80/layers/base.dtsi

# 5. Validate
./scripts/validation.sh

# 6. Commit
git add boards/
git commit -m "Update base layer"
```

---

## What's Shared vs Board-Specific

### Fully shared (update once, all boards get it)

| Component | Why portable |
|---|---|
| All macros | Pure key sequences, no position refs |
| HRM hold/tap macros | Reference letters (A, S, D, F…), not positions |
| HRM timing defines | Just numbers |
| Mod-morphs | Pure modifier logic |
| Autoshift chain | Pure behavior logic |
| Layer index defines | Shared convention |
| Bluetooth behaviors | Universal |
| Non-positional behaviors | `num_ht`, `bspc_word`, `thumb_v2_TKZ`, arrow taps |

### Shared with positional indirection (resolved per-board at compile time)

| Component | What varies |
|---|---|
| HRM bilateral behaviors | `hold-trigger-key-positions` → resolved via `HRM_*_TRIGGER_POSITIONS` |
| F-key combos | `key-positions` → same logical names, different physical numbers |

### Board-specific (maintained per-board, synced for shared positions)

| Component | Why unique |
|---|---|
| `positions.dtsi` | Physical key matrix numbers differ |
| `position_groups.dtsi` | Different key counts per hand |
| Layer bindings | Different number of keys per row — synced via `keymapsync.sh` |
| `board_meta.dtsi` | Trackpad, RGB, shield config |
| SliceMK exclusions | `magic.dtsi`, `pointing.h` (uses old mouse API) |

---

## Position Group Macros (HRM)

Each board's `position_groups.dtsi` defines which physical key numbers belong to each hand:

```c
// boards/go60/position_groups.dtsi
#define LEFT_HAND_KEYS \
  POS_LH_C1R1 POS_LH_C2R1 ... POS_LH_C4R5

#define RIGHT_HAND_KEYS \
  POS_RH_C1R1 POS_RH_C2R1 ... POS_RH_C4R5

#define THUMB_KEYS \
  POS_LH_T1 POS_LH_T2 POS_LH_T3 \
  POS_RH_T1 POS_RH_T2 POS_RH_T3

#define HRM_LEFT_TRIGGER_POSITIONS   RIGHT_HAND_KEYS THUMB_KEYS
#define HRM_RIGHT_TRIGGER_POSITIONS  LEFT_HAND_KEYS  THUMB_KEYS
```

`shared/homeRowMods/hrm_behaviors.dtsi` references these macros. Glove80 and SliceMK include more positions in their groups (extra rows, inner columns, thumb extras) — this is correct; more trigger positions means more keys that activate a bilateral hold.

---

## Validation

`scripts/validation.sh` runs 18 checks before every CI build. Key checks:

- All required files exist
- All 19 layer files present per board; correct count included in each keymap
- Position counts match (go60=60, glove80=80, slicemk=77)
- Binding counts per layer match expected key count per board
- Combo DTS wrapper present in board keymaps, absent from shared combo files
- All required shared includes present in each board keymap
- SliceMK exclusions enforced (`magic.dtsi`, `pointing.h` must not appear)
- Include ordering correct (`layers.dtsi` + `global_timings.dtsi` before `board_meta.dtsi`)
- Behavior/macro includes are inside `/ { }` block, not top-level
- No duplicate DTS labels in shared files
- All `&label` references in layers/combos resolve to known behaviors
- Layer index continuity (no gaps in 0–18 sequence)

---

## Board-Specific Notes

### Go60

- Uses `moergo-sc/zmk` (MoErgo fork with Cirque trackpad and new pointing API)
- Built with Nix (`build/go60.nix`)
- Cirque trackpad config in `board_meta.dtsi`
- Uses `zmk/pointing.h` and `zmk/input_transform.h`

### Glove80

- Uses `moergo-sc/zmk` (same fork as Go60)
- Built with Nix (`build/glove80.nix`)
- 80 keys: adds function row (10), inner thumb row (6), extended bottom row vs Go60
- Glove80-only positions: `POS_LH/RH_C*R0`, `POS_LH/RH_C*R4i`, `POS_LH/RH_C*R5`

### SliceMK ErgoDox Lite

- Uses `slicemk/zmk` (different fork — old mouse API, no RGB_STATUS)
- Built with west via GitHub Actions reusable workflow (`zmkfirmware/zmk/.github/workflows/build-user-config.yml`)
- 77 keys: adds inner columns (`POS_LH/RH_C0R*`), extended bottom row, extra thumb rows (T4–T6), one special top key
- Magic layer excluded from keymap (file exists but not included)
- Uses `zmk/mouse.h` instead of `zmk/pointing.h`
