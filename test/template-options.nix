{ pkgs }:
let
  evaluate =
    module:
    (import (pkgs.path + "/nixos/lib/eval-config.nix") {
      system = pkgs.stdenv.hostPlatform.system;
      modules = [
        ../modules/age.nix
        module
      ];
    }).config;
  valid =
    config:
    builtins.all (
      a: !(pkgs.lib.hasPrefix "agenix:" a.message || pkgs.lib.hasPrefix "age.identityPaths" a.message)
    ) (builtins.filter (a: !a.assertion) config.assertions);
  literal = evaluate {
    age.identityPaths = [ ];
    age.derivedSecrets.literal.template = pkgs.writeText "literal-template" "public text";
    age.derivedSecrets.disabled.enable = false;
  };
  disabledInput = evaluate (
    { config, ... }: {
      age.secrets.disabled.enable = false;
      age.derivedSecrets.output = {
        template = ./template-options.nix;
        secrets = [ config.age.secrets.disabled ];
      };
    }
  );
  missingInput = evaluate {
    age.derivedSecrets.output = {
      template = ./template-options.nix;
      secrets = [
        {
          name = "missing";
          file = ../example/secret1.age;
        }
      ];
    };
  };
  collision = evaluate {
    age.identityPaths = [ "/test-key" ];
    age.secrets.duplicate.file = ../example/secret1.age;
    age.derivedSecrets.duplicate.template = ./template-options.nix;
  };
in
assert literal.age.enable && valid literal;
assert !valid disabledInput;
assert !valid missingInput;
assert !valid collision;
pkgs.runCommand "agenix-template-options" { } ''touch "$out"''
