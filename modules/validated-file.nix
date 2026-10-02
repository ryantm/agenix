{
  lib,
  pkgs,
  enable,
}:
file:
if enable && (builtins.isPath file || lib.hasPrefix "${builtins.storeDir}/" (toString file)) then
  pkgs.runCommand "agenix-checked-secret"
    {
      src = file;
      nativeBuildInputs = [ (pkgs.buildPackages.callPackage ../pkgs/validate-ciphertext.nix { }) ];
    }
    ''
      agenix-validate "$src"
      cp -- "$src" "$out"
    ''
else
  file
