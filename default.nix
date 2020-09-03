{ pkgs ? import <nixpkgs> {} }:
rec {
  age-nix = pkgs.writeScriptBin "age-nix" ''
    exit 0
  '';
}
