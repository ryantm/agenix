{ pkgs }:
let
  evaluate =
    openssh:
    (import (pkgs.path + "/nixos/lib/eval-config.nix") {
      inherit pkgs;
      system = pkgs.stdenv.hostPlatform.system;
      modules = [
        ../modules/age.nix
        {
          services.openssh = {
            hostKeys = [
              {
                type = "ed25519";
                path = "/custom/ed25519";
              }
              {
                type = "rsa";
                path = "/custom/rsa";
              }
              {
                type = "ecdsa";
                path = "/custom/ecdsa";
              }
            ];
          }
          // openssh;
        }
      ];
    }).config.age.identityPaths;
  supported = [
    "/custom/ed25519"
    "/custom/rsa"
  ];
in
assert
  evaluate {
    enable = false;
    generateHostKeys = true;
  } == supported;
assert
  evaluate {
    enable = true;
    generateHostKeys = false;
  } == supported;
assert
  evaluate {
    enable = false;
    generateHostKeys = false;
  } == [ ];
pkgs.runCommand "agenix-identity-defaults" { } "touch $out"
