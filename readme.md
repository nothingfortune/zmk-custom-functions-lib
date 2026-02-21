# zmk-custom-functions-lib

Shared ZMK firmware configuration for three keyboards, built automatically on every commit to `main`.

---

## Supported keyboards

| Keyboard | ZMK fork | Build system | PCB |
|---|---|---|---|
| **Go60** | `moergo-sc/zmk` | Nix | go60_lh / go60_rh |
| **Glove80** | `moergo-sc/zmk` | Nix | glove80_lh / glove80_rh |
| **SliceMK ErgoDox Lite** | `slicemk/zmk` | west (GitHub Actions) | slicemk_ergodox_202109 (dongleless) |

---

## How it works

### Repository layout

```
zmk-custom-functions-lib/
│
├── shared/                         # Cross-keyboard behaviors (included by all boards)
│   ├── layers.dtsi                 # LAYER_* index constants (0-18)
│   ├── macros.dtsi
│   ├── behaviors.dtsi
│   ├── modMorphs.dtsi
│   ├── autoshift.dtsi
│   ├── bluetooth.dtsi
│   ├── magic.dtsi
│   ├── homeRowMods/
│   │   ├── hrm_timings.dtsi
│   │   ├── hrm_macros.dtsi
│   │   └── hrm_behaviors.dtsi
│   └── combos/
│       ├── combos_common.dtsi      # Raw combo node definitions (no DTS wrapper)
│       └── combos_fkeys.dtsi
│
├── boards/
│   ├── go60/
│   │   ├── positions.dtsi          # POS_LH_CxRx / POS_RH_CxRx defines (60 keys)
│   │   ├── position_groups.dtsi    # LEFT_HAND_KEYS, RIGHT_HAND_KEYS, THUMB_KEYS, HRM trigger groups
│   │   ├── board_meta.dtsi         # Go60-specific: trackpad, RGB, tap-dance
│   │   ├── go60.keymap             # Top-level keymap (includes everything)
│   │   ├── go60.conf               # Kconfig options (RGB, sleep, BT power)
│   │   └── layers/                 # One .dtsi per layer (19 total)
│   │       ├── base.dtsi
│   │       ├── typing.dtsi
│   │       └── ...
│   ├── glove80/                    # Same structure; layers are &trans stubs
│   └── slicemk/                    # Same structure; layers are &trans stubs
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
├── build.yaml                      # SliceMK board/shield matrix for west build
└── .github/workflows/build.yml     # CI: builds all 3 boards in parallel
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

### Key position naming

Positions use logical names so combos and HRM behaviors work across all boards:

- `POS_LH_CxRx` — left hand, column x, row x (1-indexed)
- `POS_RH_CxRx` — right hand, column x, row x
- `POS_LH_T1/T2/T3` — left thumb cluster
- `POS_RH_T1/T2/T3` — right thumb cluster

Each board's `positions.dtsi` maps these names to its physical key numbers.

---

## Building firmware

### Automatic (recommended)

Push or merge to `main`. GitHub Actions builds all three keyboards in parallel. Firmware files are uploaded as artifacts on the [Actions](../../actions) page and kept for 90 days.

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

### Editing a layer

Open the relevant layer file for your board:

```
boards/<board>/layers/<layer_name>.dtsi
```

Each file contains a single ZMK layer node with a `bindings` list. The binding order matches the position numbers in that board's `positions.dtsi`.

**Go60 layers** have real bindings. **Glove80 and SliceMK layers** are currently `&trans` stubs — replace them as you build out those layouts.

### Adding a combo

Edit `shared/combos/combos_common.dtsi` (or `combos_fkeys.dtsi` for F-key combos). The files contain raw combo nodes — do **not** add a `/ { combos { ... }; };` wrapper; that wrapper lives in each board's keymap file.

Use the logical position names (`POS_LH_C2R3`, etc.) so the combo works on all boards that share the same finger mapping.

### Adding a behavior or macro

Edit the relevant shared file:

- New behavior → `shared/behaviors.dtsi`
- New macro → `shared/macros.dtsi`
- New mod-morph → `shared/modMorphs.dtsi`
- HRM timing change → `shared/homeRowMods/hrm_timings.dtsi`

### Board-specific hardware config (Go60: trackpad, RGB, etc.)

Edit `boards/go60/board_meta.dtsi`. Glove80 and SliceMK stubs are in their respective `board_meta.dtsi` files.

### Adding or removing a layer

1. Add/remove the `#define LAYER_Name N` entry in `shared/layers.dtsi` (keep indices contiguous).
2. Create/delete the corresponding `layers/<name>.dtsi` file in **each** board's `layers/` directory.
3. Add/remove the `#include "layers/<name>.dtsi"` line in **each** board's keymap file (inside the `/ { keymap { ... }; };` block).

---

## SliceMK PCB revision

To verify your PCB revision, put the keyboard into bootloader mode and check `INFO_UF2.TXT` — the `Model` field shows the board name. Common revisions:

| Model field | board value in build.yaml |
|---|---|
| `slicemk_ergodox_202109` | `slicemk_ergodox_202109` (this repo) |
| `slicemk_ergodox_202108_green_left` | `slicemk_ergodox_202108_green_left` |
| `slicemk_ergodox_202104` | `slicemk_ergodox_202104` |

Update `build.yaml` and `config/slicemk_ergodox_leftcentral.conf` if your board differs.
