{ pkgs }:
let
  evaluate =
    mode: sysusers:
    (import (pkgs.path + "/nixos/lib/eval-config.nix") {
      inherit pkgs;
      system = pkgs.stdenv.hostPlatform.system;
      modules = [
        ../modules/age.nix
        ({ config, ... }: {
          systemd.sysusers.enable = sysusers;
          age = {
            installationMode = mode;
            identityPaths = [ "/key" ];
            secrets.password.file = ../example/passwordfile-user1.age;
          };
          users.users.tester = {
            isNormalUser = true;
            hashedPasswordFile = config.age.secrets.password.path;
          };
        })
      ];
    }).config;
  late = evaluate "systemd" true;
  early = evaluate "activation" true;
  traditional = evaluate "activation" false;
  passwordAssertion =
    config:
    pkgs.lib.findFirst (
      assertion: pkgs.lib.hasPrefix "agenix:" assertion.message
    ) (throw "missing password-mode assertion") config.assertions;
in
assert !(passwordAssertion late).assertion;
assert (passwordAssertion early).assertion;
assert (passwordAssertion traditional).assertion;
assert !(late.system.activationScripts ? agenixInstall);
assert !(early.system.activationScripts ? agenixInstall);
assert traditional.system.activationScripts ? agenixInstall;
assert builtins.elem "systemd-sysusers.service"
  early.systemd.services.agenix-install-secrets.before;
assert builtins.elem "systemd-sysusers.service" late.systemd.services.agenix-install-secrets.after;
pkgs.runCommand "agenix-systemd-mode-options" { } "touch $out"
