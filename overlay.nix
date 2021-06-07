final: prev:
{
  agenix = prev.callPackage ./pkgs/agenix.nix { };
  age-plugin-yubikey = prev.callPackage ./pkgs/age-plugin-yubikey.nix { };
}
