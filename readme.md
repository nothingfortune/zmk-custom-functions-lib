# zmk-multi-keyboard-build

Shared ZMK firmware configuration for three keyboards, built automatically on every commit to `main`.

---

## Supported keyboards

| Keyboard | ZMK fork | Build system | PCB |
|---|---|---|---|
| **Go60** | `moergo-sc/zmk` | Nix | go60_lh / go60_rh |
| **Glove80** | `moergo-sc/zmk` | Nix | glove80_lh / glove80_rh |
| **SliceMK ErgoDox Lite** | `slicemk/zmk` | west (GitHub Actions) | slicemk_ergodox_202207_green_left |

---

## How it works

### Repository layout

```
zmk-multi-keyboard-build/
│
├── shared/                         # Cross-keyboard behaviors (included by all boards)
│   ├── layers.dtsi                 # LAYER_* index constants (0–18)
│   ├── macros.dtsi
│   ├── behaviors.dtsi
│   ├── modMorphs.dtsi
│   ├── autoshift.dtsi
│   ├── bluetooth.dtsi
│   ├── magic.dtsi                  # RGB status macro (excluded from SliceMK)
│   ├── global_timings.dtsi
│   ├── homeRowMods/
│   │   ├── hrm_macros.dtsi
│   │   └── hrm_behaviors.dtsi
│   └── combos/
│       ├── combos_common.dtsi      # Raw combo node definitions (no DTS wrapper)
│       └── combos_fkeys.dtsi
│
├── boards/
│   ├── go60/                       # Source of truth — edit here first
│   │   ├── positions.dtsi          # POS_LH_CxRx / POS_RH_CxRx defines (60 keys)
│   │   ├── position_groups.dtsi    # LEFT_HAND_KEYS, RIGHT_HAND_KEYS, THUMB_KEYS, HRM trigger groups
│   │   ├── board_meta.dtsi         # Go60-specific: trackpad, RGB, tap-dance
│   │   ├── go60.keymap
│   │   ├── go60.conf
│   │   └── layers/                 # 19 layer files — real bindings
│   │       ├── base.dtsi
│   │       ├── typing.dtsi
│   │       └── ...
│   ├── glove80/                    # Same structure; shared positions synced from go60
│   │   └── layers/                 # 80-key grid; extra positions are board-specific
│   └── slicemk/                    # Same structure; shared positions synced from go60
│       └── layers/                 # 77-key grid; extra positions are board-specific
│
├── boards/translations/            # Positional index maps used by keymapsync.sh
│   ├── go60_to_glove80.txt         # go60 binding index → glove80 binding index (60 pairs)
│   ├── go60_to_slicemk.txt         # go60 binding index → slicemk binding index (60 pairs)
│   └── glove80_to_go60.txt         # glove80 binding index → go60 binding index (reverse)
│
├── config/                         # SliceMK west entry point
│   ├── west.yml                    # Declares slicemk/zmk as ZMK dependency
│   ├── slicemk_ergodox.keymap      # Thin wrapper: includes ../boards/slicemk/slicemk.keymap
│   └── slicemk_ergodox_leftcentral.conf
│
├── build/
│   ├── go60.nix                    # Nix derivation for Go60 firmware
│   └── glove80.nix                 # Nix derivation for Glove80 firmware
│
├── scripts/
│   ├── keymapsync.sh               # Sync go60 layers → glove80 + slicemk (go60 is source of truth)
│   ├── diff_layers.sh              # Compare layer bindings across boards
│   └── validation.sh               # Structural validation (run by CI before builds)
│
├── docs/
│   ├── positionmapping.md          # Cross-board position name ↔ physical index reference
│   └── zmk-sync-architecture.md   # Architecture overview
│
├── build.yaml                      # SliceMK board/shield matrix for west build
└── .github/workflows/build.yml     # CI: validates, then builds all 3 boards in parallel
```

### Layers (19 total)

| # | Name | File |
|---|---|---|
| 0 | Base | `layers/base.dtsi` |
| 1 | Typing | `layers/typing.dtsi` |
| 2 | Autoshift | `layers/autoshift.dtsi` |
| 3–6 | HRM Left (Pinky/Ring/Middy/Index) | `layers/hrm_left_*.dtsi` |
| 7–10 | HRM Right (Pinky/Ring/Middy/Index) | `layers/hrm_right_*.dtsi` |
| 11 | Cursor | `layers/cursor.dtsi` |
| 12 | Keypad | `layers/keypad.dtsi` |
| 13 | Symbol | `layers/symbol.dtsi` |
| 14–17 | Mouse / MouseSlow / MouseFast / MouseWarp | `layers/mouse*.dtsi` |
| 18 | Magic | `layers/magic.dtsi` |

> SliceMK excludes the Magic layer (RGB_STATUS is unsupported in the `slicemk/zmk` fork), so it has 18 active layers.

### Key position naming

Positions use logical names so combos and HRM behaviors compile correctly across all boards:

- `POS_LH_CxRx` — left hand, column x, row x (1-indexed)
- `POS_RH_CxRx` — right hand, column x, row x
- `POS_LH_T1/T2/T3` — left thumb cluster
- `POS_RH_T1/T2/T3` — right thumb cluster

Each board's `positions.dtsi` maps these names to its physical key numbers. See `docs/positionmapping.md` for the full cross-board reference table.

---

## Building firmware

### Automatic (recommended)

Push or merge to `main`. GitHub Actions validates the config, then builds all three keyboards in parallel. Firmware files are uploaded as artifacts on the [Actions](../../actions) page and kept for 90 days.

### Manual — Go60 or Glove80 (Nix)

Requires Nix with the `moergo-glove80-zmk-dev` Cachix cache for fast builds.

```sh
# Clone the moergo ZMK fork alongside this repo
git clone https://github.com/moergo-sc/zmk src

# Build Go60
nix-build build/go60.nix --arg firmware 'import ./src {}' -o result-go60
# Output: result-go60/go60.uf2

# Build Glove80
nix-build build/glove80.nix --arg firmware 'import ./src {}' -o result-glove80
# Output: result-glove80/glove80.uf2
```

### Manual — SliceMK (west)

SliceMK uses a standard west-based build. See the [slicemk/zmk](https://github.com/slicemk/zmk) repo for local build instructions, or trigger a build via the GitHub Actions `workflow_dispatch` button.

---

## Output files

| Board | Artifact name | File |
|---|---|---|
| Go60 | `go60-firmware` | `go60.uf2` — flash left half, then right half |
| Glove80 | `glove80-firmware` | `glove80.uf2` — flash left half, then right half |
| SliceMK | `firmware` | `.uf2` file — flash the left-central half |

Download from the Actions run page → click the job → scroll to **Artifacts**.

---

## Making keymap changes

### The sync model — go60 is source of truth

Edit layers in `boards/go60/layers/`, then run:

```sh
./scripts/keymapsync.sh
```

This reads the translation maps in `boards/translations/` and propagates every go60 binding to the matching position on glove80 and slicemk. Positions that only exist on the target board (glove80 function row, slicemk inner columns, extra thumb keys) are left untouched.

After syncing, review the diffs and commit all three boards together.

### Editing a layer

Open the go60 layer file first:

```
boards/go60/layers/<layer_name>.dtsi
```

Each file contains a single ZMK layer node with a `bindings` list. The binding order matches the position numbers in `boards/go60/positions.dtsi`.

After editing go60, run `keymapsync.sh`, then manually edit any board-specific positions in `boards/glove80/layers/` or `boards/slicemk/layers/` as needed.

### Inspecting layers across boards

```sh
# Show stub/fill status table for all layers × boards
./scripts/diff_layers.sh

# Show go60 bindings for a layer (numbered by key position)
./scripts/diff_layers.sh base

# Show a specific board's layer
./scripts/diff_layers.sh base glove80

# Diff two boards for a layer
./scripts/diff_layers.sh base go60 glove80
```

### Adding a combo

Edit `shared/combos/combos_common.dtsi` (or `combos_fkeys.dtsi` for F-key combos). The files contain raw combo nodes — do **not** add a `/ { combos { ... }; };` wrapper; that wrapper lives in each board's keymap file.

Use the logical position names (`POS_LH_C2R3`, etc.) so the combo works on all boards that share the same finger mapping.

### Adding a behavior or macro

Edit the relevant shared file:

- New behavior → `shared/behaviors.dtsi`
- New macro → `shared/macros.dtsi`
- New mod-morph → `shared/modMorphs.dtsi`
- Timing change → `shared/global_timings.dtsi`

### Board-specific hardware config (Go60: trackpad, RGB, etc.)

Edit `boards/go60/board_meta.dtsi`. Glove80 and SliceMK stubs are in their respective `board_meta.dtsi` files.

### Adding or removing a layer

1. Add/remove the `#define LAYER_Name N` entry in `shared/layers.dtsi` (keep indices contiguous).
2. Create/delete the corresponding `layers/<name>.dtsi` file in **each** board's `layers/` directory.
3. Add/remove the `#include "layers/<name>.dtsi"` line in **each** board's keymap file (inside the `/ { keymap { ... }; };` block).

### Validating the repo structure

```sh
./scripts/validation.sh
```

Runs 18 structural checks: required files, layer counts, binding counts per board, combo wrapper placement, include ordering, duplicate DTS labels, undefined `&label` references, and more. Also runs automatically in CI as the first job before any firmware build.

---

## SliceMK PCB revision

To verify your PCB revision, put the keyboard into bootloader mode and check `INFO_UF2.TXT` — the `Model` field shows the board name. Common revisions:

| Model field | board value in build.yaml |
|---|---|
| `slicemk_ergodox_202207_green_left` | `slicemk_ergodox_202207_green_left` (this repo) |
| `slicemk_ergodox_202109` | `slicemk_ergodox_202109` |
| `slicemk_ergodox_202108_green_left` | `slicemk_ergodox_202108_green_left` |
| `slicemk_ergodox_202104` | `slicemk_ergodox_202104` |

Update `build.yaml` and `config/slicemk_ergodox_leftcentral.conf` if your board differs.
