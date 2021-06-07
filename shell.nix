{ pkgs ? import <nixpkgs> { }
, agenix ? pkgs.callPackage ./pkgs/agenix.nix { }
, age-plugin-yubikey ? pkgs.callPackage ./pkgs/age-plugin-yubikey.nix { }
, ...
}:
pkgs.mkShell { buildInputs = [ agenix age-plugin-yubikey ]; }
