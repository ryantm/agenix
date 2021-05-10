{ pkgs ? import <nixpkgs> { } }:

pkgs.callPackage ./pkgs/agenix.nix { }

