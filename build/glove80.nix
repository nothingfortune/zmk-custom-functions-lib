/* Glove80 Nix build — moergo-sc/zmk fork */
{ pkgs ? import <nixpkgs> {}
, firmware ? import ../src {}
}:

let
  repo = ./..;

  glove80_lh = firmware.zmk.override {
    board = "glove80_lh";
    keymap  = "${repo}/boards/glove80/glove80.keymap";
    kconfig = "${repo}/boards/glove80/glove80.conf";
  };

  glove80_rh = firmware.zmk.override {
    board = "glove80_rh";
    keymap  = "${repo}/boards/glove80/glove80.keymap";
    kconfig = "${repo}/boards/glove80/glove80.conf";
  };

in firmware.combine_uf2 glove80_lh glove80_rh "glove80"
