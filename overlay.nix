final: prev:
{
  agenix = prev.callPackage ./pkgs/agenix.nix { };
  rage = pkgs.callPackage ./pkgs/rage.nix  {};
}
