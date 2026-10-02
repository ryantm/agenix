{ pkgs, home-manager }:
let
  config =
    (home-manager.lib.homeManagerConfiguration {
      inherit pkgs;
      modules = [
        ../modules/age-home.nix
        {
          home.username = "tester";
          home.homeDirectory = "/home/tester";
          home.stateVersion = "26.05";
          age = {
            identityPaths = [
              "${pkgs.writeText "empty-identity" ""}"
              "${../example_keys/user1}"
            ];
            secrets.secret.file = ../example/secret2.age;
            secretsDir = "$TMPDIR/secrets";
            secretsMountPoint = "$TMPDIR/generations";
          };
        }
      ];
    }).config;
in
pkgs.runCommand "agenix-home-empty-identity" { } ''
  ${builtins.head config.systemd.user.services.agenix.Service.ExecStart}
  test "$(cat "$TMPDIR/secrets/secret")" = 'world!'
  touch "$out"
''
