{ pkgs }:
let
  plugin = pkgs.writeShellScriptBin "age-plugin-fixture" ''
    # The inherited PATH must remain usable by plugins too.
    printf 'plugin ran\n' | grep -q 'plugin ran'
    touch /run/agenix-plugin-ran
  '';
  ageWrapper = pkgs.writeShellScript "age-with-plugin" ''
    set -e
    age-plugin-fixture
    exec ${pkgs.age}/bin/age "$@"
  '';
  makeNode = sysusers: {
    imports = [ ../modules/age.nix ];
    systemd.sysusers.enable = sysusers;
    services.userborn.enable = false;
    age = {
      ageBin = "${ageWrapper}";
      pluginPackages = [ plugin ];
      identityPaths = [ "${../example_keys/system1}" ];
      secrets.secret.file = ../example/secret1.age;
    };
  };
in
pkgs.testers.nixosTest {
  name = "agenix-plugin-path";
  nodes.activation = makeNode false;
  nodes.sysusers = makeNode true;
  testScript = ''
    for machine in [activation, sysusers]:
        machine.start()
        machine.wait_for_unit("multi-user.target")
        machine.succeed("test -f /run/agenix-plugin-ran")
        assert machine.succeed("cat /run/agenix/secret").strip() == "hello"
        machine.shutdown()
  '';
}
