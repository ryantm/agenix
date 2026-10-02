{ pkgs }:
let
  inherit (pkgs) lib;
  validate = import ../modules/validated-file.nix {
    inherit lib pkgs;
    enable = true;
  };
  unchecked = import ../modules/validated-file.nix {
    inherit lib pkgs;
    enable = false;
  };
  invalid = pkgs.writeText "invalid.age" "private-marker-must-not-appear";
  emptyFailure = pkgs.testers.testBuildFailure (validate (pkgs.writeText "empty.age" ""));
  invalidFailure = pkgs.testers.testBuildFailure (validate invalid);
  validator = pkgs.callPackage ../pkgs/validate-ciphertext.nix { };
in
assert validate "/run/agenix/ciphertext.age" == "/run/agenix/ciphertext.age";
assert unchecked invalid == invalid;
pkgs.runCommand "agenix-ciphertext-validation" { nativeBuildInputs = [ pkgs.python3 ]; } ''
  cmp ${validate ../example/secret1.age} ${../example/secret1.age}
  cmp ${validate "${../example/armored-secret.age}"} ${../example/armored-secret.age}
  grep -q 'invalid age header or armor' ${emptyFailure}/testBuildFailure.log
  grep -q 'invalid age header or armor' ${invalidFailure}/testBuildFailure.log
  if grep -q private-marker-must-not-appear ${invalidFailure}/testBuildFailure.log; then exit 1; fi
  python3 ${./ciphertext-validation.py} ${lib.getExe validator} ${pkgs.age}/bin/age ${../example} ${../example_keys/user1.pub}
  touch "$out"
''
