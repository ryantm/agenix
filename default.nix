{ pkgs ? import <nixpkgs> {} }:
{
  agenix = pkgs.callPackage ./pkgs/agenix.nix  {};
}
