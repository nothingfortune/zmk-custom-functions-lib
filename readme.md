# Shared ZMK Behaviors Library Setup

This guide explains how to create and use a shared ZMK behaviors library across multiple keyboard repositories, keeping your custom behaviors in sync.

---

## 1. Create the Shared Behaviors Repo

1. On GitHub, create a new repository (e.g. `zmk-behaviors-lib`).
2. Locally, clone it and create a structure like:
    ```
    zmk-behaviors-lib/
      dts/
        behaviors/
          hold-taps.dtsi
          mod-morphs.dtsi
          macros.dtsi
    ```
3. Copy your custom behavior definitions (from each board's keymap) into these `.dtsi` files, grouping by type.
4. Commit and push.

---

## 2. Add the Library as a West Module in Each Board Repo

1. In each keyboard repo, edit `west.yml`:
    ```yaml
    manifest:
      projects:
        - name: zmk-behaviors-lib
          url: https://github.com/YOURNAME/zmk-behaviors-lib
          revision: main
    ```
2. Run:
    ```sh
    west update
    ```

---


## 3. Include Shared Behaviors in Your Keymap

At the top of your keymap file, include the custom behavior files you need. For example:
```dts
#include <zmk-custom-functions-lib/dts/behaviors.dtsi>
#include <zmk-custom-functions-lib/dts/combos.dtsi>
#include <zmk-custom-functions-lib/dts/holdTaps.dtsi>
#include <zmk-custom-functions-lib/dts/homeRowMods.dtsi>
#include <zmk-custom-functions-lib/dts/layerBehaviors.dtsi>
#include <zmk-custom-functions-lib/dts/macros.dtsi>
#include <zmk-custom-functions-lib/dts/modMorphs.dtsi>
```

> **Tip:** Only include the .dtsi files for the behaviors you actually use in your keymap.

---

## 4. Citing and Using Behaviors in Your Keymap

Once included, you can reference the custom behaviors by their node labels as defined in the .dtsi files. For example, if you have this in your homeRowMods.dtsi:
```dts
HRM_lh_index_TKZ: HRM_lh_index_TKZ {
  compatible = "zmk,behavior-hold-tap";
  // ...
};
```
You can use it in your keymap like this:
```dts
&HRM_lh_index_TKZ MOD_LCTL KC_A
```

Replace `MOD_LCTL` and `KC_A` with the desired modifier and keycode for your layout.

---

---


## 5. Syncing Updates

- When you update a behavior in the shared repo, just `git pull` and `west update` in each board repo to sync.

---

## 5. Tips

- Keep behaviors generic and parameterized for maximum reuse.
- Use version tags/releases in the shared repo for stability.
- Document each behavior in the `.dtsi` files for clarity.

---

## 6. Troubleshooting

- If a behavior is not found, check the include path and that `west update` completed successfully.
- If you need board-specific overrides, define those after the shared includes in your keymap.

---


## Example Directory Layout

```
/your-keyboard-repo/
  config/
    myboard.keymap
  west.yml
  ...
  modules/
    zmk-custom-functions-lib/
      dts/homeRowMods.dtsi
      dts/macros.dtsi
      dts/hold-taps.dtsi
```

---

## 7. Keeping Everything in Sync

- Make all behavior changes in the shared repo.
- Pull and update in each board repo as needed.
- Use GitHub Actions in each board repo as before; no changes needed for CI.

---

**You now have a maintainable, DRY setup for ZMK behaviors across all your boards!**
