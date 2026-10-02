{ pkgs, home-manager }:
let
  wrapper = pkgs.writeShellScriptBin "age-wrapper" ''
    echo wrapper-invoked >&2
    exec ${pkgs.age}/bin/age "$@"
  '';
  makeConfig =
    name: extra:
    (home-manager.lib.homeManagerConfiguration {
      inherit pkgs;
      modules = [
        ../modules/age-home.nix
        {
          home.username = "tester";
          home.homeDirectory = "/home/tester";
          home.stateVersion = "26.05";
          age = {
            identityPaths = [ "${../example_keys/user1}" ];
            secrets.secret.file = ../example/secret2.age;
            secretsDir = "$TMPDIR/${name}/secrets";
            secretsMountPoint = "$TMPDIR/${name}/generations";
          }
          // extra;
        }
      ];
    }).config;
  packageConfig = makeConfig "package" { package = wrapper; };
  commandConfig = makeConfig "command" {
    package = pkgs.writeShellScriptBin "unused-age" "exit 99";
    ageBin = "${wrapper}/bin/age-wrapper";
  };
in
assert packageConfig.age.ageBin == "${wrapper}/bin/age-wrapper";
pkgs.runCommand "agenix-home-age-bin" { } ''
  ${builtins.head packageConfig.systemd.user.services.agenix.Service.ExecStart} 2> package.log
  grep -q wrapper-invoked package.log
  test "$(cat "$TMPDIR/package/secrets/secret")" = 'world!'
  ${builtins.head commandConfig.systemd.user.services.agenix.Service.ExecStart} 2> command.log
  grep -q wrapper-invoked command.log
  test "$(cat "$TMPDIR/command/secrets/secret")" = 'world!'
  touch "$out"
''
