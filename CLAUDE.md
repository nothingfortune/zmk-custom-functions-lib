# Claude Instructions — zmk-multi-keyboard-build

## What this repo is

ZMK firmware for three split keyboards sharing a single keymap library. **Go60 is the source of truth.** Glove80 and SliceMK are synced from it.

---

## Running keymapsync.sh

```sh
bash scripts/keymapsync.sh
```

The script requires **bash 4+** (macOS ships bash 3.2). The script self-re-execs using `/opt/homebrew/bin/bash` or `/usr/local/bin/bash` automatically — plain `bash` is enough to invoke it.

Do **not** add `set -x` to the script.

---

## Typical edit workflow

1. Edit the layer in `boards/go60/layers/<name>.dtsi`
2. Run `bash scripts/keymapsync.sh` to propagate changes to glove80 and slicemk
3. If needed, manually adjust board-specific positions in `boards/glove80/layers/` or `boards/slicemk/layers/`
4. Run `bash scripts/validation.sh` to check structural integrity
5. Commit all three boards together

---

## Layer structure

21 layers defined in `shared/layers.dtsi` (LAYER_* constants 0–20). Each board has a `layers/` directory with one `.dtsi` file per layer. SliceMK **excludes** `magic.dtsi` (magic.dtsi exists but is not `#include`d in `slicemk.keymap`).

Layer files contain a single ZMK layer node with a `bindings = < ... >;` block. Binding order matches `boards/<board>/positions.dtsi`.

---

## Translation maps

Located in `boards/translations/`. Format: `src_idx dst_idx` pairs, one per line, `#` for comments. Each map has exactly 60 entries (the 60 positions go60 and the target board share).

```
# go60_to_glove80.map
0 10
1 11
...
```

Maps are derived by matching `POS_*` names between `boards/go60/positions.dtsi` and the target board's `positions.dtsi`.

---

## Key position naming

All boards define the same logical names in `positions.dtsi`:

- `POS_LH_CxRy` — left hand, column x (rightmost=1... or 6 depending on board), row y (top=1)
- `POS_RH_CxRy` — right hand, column x, row y
- `POS_LH_T1/T2/T3` — left thumb cluster
- `POS_RH_T1/T2/T3` — right thumb cluster

Board-specific extras (Glove80: function row R0, inner columns; SliceMK: inner columns C0, extra thumbs T4-T6) map to additional physical keys not covered by the translation maps.

---

## Shared code — where to edit

| Task | File |
|---|---|
| New behavior | `shared/behaviors.dtsi` |
| New macro | `shared/macros.dtsi` |
| New mod-morph | `shared/modMorphs.dtsi` |
| Timing changes | `shared/global_timings.dtsi` |
| New combo | `shared/combos/combos_common.dtsi` |
| HRM behaviors | `shared/homeRowMods/hrm_behaviors.dtsi` |
| Layer index constants | `shared/layers.dtsi` |

---

## Board-specific files

| Board | Key count | ZMK fork | Build |
|---|---|---|---|
| go60 | 60 | moergo-sc/zmk | Nix |
| glove80 | 80 | moergo-sc/zmk | Nix |
| slicemk | 77 | slicemk/zmk | west |

Each board has: `positions.dtsi`, `position_groups.dtsi`, `board_meta.dtsi`, `<board>.keymap`, `<board>.conf`, `layers/`.

---

## Adding or removing a layer

1. Add/remove `#define LAYER_Name N` in `shared/layers.dtsi` (keep 0-based, contiguous)
2. Create/delete `layers/<name>.dtsi` in **all three** boards' `layers/` directories
3. Add/remove `#include "layers/<name>.dtsi"` in **all three** boards' keymap files
4. Update expected layer counts in `scripts/validation.sh`

---

## Combos

Raw combo nodes go in `shared/combos/combos_common.dtsi`. Do **not** add a `/ { combos { ... }; };` wrapper — the wrapper already exists in each board's keymap file.

---

## Validation

```sh
bash scripts/validation.sh
```

18 structural checks. Runs in CI before every build. If a layer count changes, update the expected counts in `validation.sh`.

---

## SliceMK constraints

- Do **not** add `#include "../../shared/magic.dtsi"` to `slicemk.keymap` — `RGB_STATUS` is unsupported in the `slicemk/zmk` fork
- Do **not** reference `pointing.h` in slicemk files
- SliceMK uses west build (not Nix); entry point is `config/west.yml`

---

## CI

`.github/workflows/build.yml` — validates first, then builds all three boards in parallel. Artifacts kept 90 days.
