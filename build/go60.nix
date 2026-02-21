/* Go60 Nix build — moergo-sc/zmk fork */
{ pkgs ? import <nixpkgs> {}
, firmware ? import ../src {}
}:

let
  repo = ./..;

  go60_left = firmware.zmk.override {
    board = "go60_lh";
    keymap  = "${repo}/boards/go60/go60.keymap";
    kconfig = "${repo}/boards/go60/go60.conf";
  };

  go60_right = firmware.zmk.override {
    board = "go60_rh";
    keymap  = "${repo}/boards/go60/go60.keymap";
    kconfig = "${repo}/boards/go60/go60.conf";
  };

in firmware.combine_uf2 go60_left go60_right "go60"
