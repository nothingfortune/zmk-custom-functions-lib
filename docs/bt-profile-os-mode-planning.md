# ZMK Bluetooth Profile-Based OS Mode Switching

## Goal
Enable automatic modifier swapping (LGUI ↔ LCTRL) based on the active Bluetooth profile, so the keyboard adapts to Mac or PC without manual layer toggling or deep keymap changes.

## Requirements
- ZMK firmware with Bluetooth profile support
- Ability to trigger layer or variable changes based on active profile
- Minimal impact on existing keymap structure

## Approach
1. **Profile Assignment**
   - Assign each Bluetooth profile to a specific OS (e.g., bt_0 = Mac, bt_3 = PC).

2. **Modifier Swap Logic**
   - Use ZMK's conditional behaviors or layers to swap LGUI and LCTRL based on the active profile.
   - Avoid deep changes to the keymap; use overlays or conditional macros.

3. **Implementation Steps**
   - Define a custom variable or layer for OS mode (e.g., `os_mac`, `os_pc`).
   - Set up profile switching behaviors to activate the correct mode when a profile is selected.
   - Use conditional key definitions or overlays to swap LGUI/LCTRL.

4. **Example Workflow**
   - User switches to bt_3 (PC profile):
     - Keyboard automatically activates `os_pc` mode.
     - All keys mapped to LGUI now send LCTRL instead.
   - User switches to bt_0 (Mac profile):
     - Keyboard activates `os_mac` mode.
     - LGUI sends Command as usual.

5. **Keymap Integration**
   - Use ZMK's `&if` or similar conditional behaviors to define keys that change based on mode.
   - Keep base keymap unchanged; add modifier overlays.

## Example (Pseudo-DTS)
```dts
// Define OS mode variables
os_mac: os_mac {}
os_pc: os_pc {}

// Profile switch behaviors
profile_switch_mac {
    compatible = "zmk,behavior-toggle";
    bindings = <&os_mac>;
}
profile_switch_pc {
    compatible = "zmk,behavior-toggle";
    bindings = <&os_pc>;
}

// Conditional key definition
key_lgui {
    compatible = "zmk,behavior-if";
    bindings = <&os_mac &kp LGUI>, <&os_pc &kp LCTRL>;
}
```

## Considerations
- Ensure profile switch keys also trigger OS mode change.
- Test for seamless switching without interfering with other layers or macros.
- Document which profile is assigned to which OS for clarity.

## Next Steps
1. Prototype the conditional modifier swap in a test keymap.
2. Integrate with Bluetooth profile switching.
3. Validate on real devices (Mac/PC).
4. Refine for minimal impact on base keymap.

---

*This document outlines a plan for seamless OS mode switching in ZMK based on Bluetooth profile, enabling modifier swaps without deep keymap changes.*
