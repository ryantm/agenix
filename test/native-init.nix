{ pkgs }:
let
  inherit (pkgs) lib;
  makeNode = late: { config, ... }: {
    imports = [ ../modules/age.nix ];
    boot.initrd.systemd.enable = true;
    system.etc.overlay.enable = true;
    services.userborn.enable = true;
    boot.postBootCommands = lib.mkForce "";
    system.nixos-init.enable = true;
    users.mutableUsers = false;
    users.users.reader = {
      isNormalUser = true;
      uid = 1000;
    }
    // lib.optionalAttrs (!late) {
      hashedPasswordFile = config.age.secrets.password.path;
    };
    # A public fixture, exposed before services by native /etc setup.
    environment.etc."agenix-test-identity".source = ../example_keys/system1;
    age.identityPaths = [ "/etc/agenix-test-identity" ];
    age.installationMode = if late then "systemd" else "activation";
    age.secrets = {
      owned = {
        file = ../example/secret1.age;
        owner = "reader";
        group = "users";
      };
    }
    // lib.optionalAttrs (!late) {
      password.file = ../example/passwordfile-user1.age;
    };
    assertions = [
      {
        assertion = !(config.system.activationScripts ? agenixInstall);
        message = "The native-init test must not install secrets through activation snippets.";
      }
    ];
    systemd.services.secret-consumer = {
      wantedBy = [ "multi-user.target" ];
      requires = [ "agenix-install-secrets.service" ] ++ lib.optional (!late) "agenix-chown.service";
      after = [ "agenix-install-secrets.service" ] ++ lib.optional (!late) "agenix-chown.service";
      serviceConfig = {
        Type = "oneshot";
        RemainAfterExit = true;
        User = "reader";
      };
      script = ''
        test "$(cat ${config.age.secrets.owned.path})" = hello
        test "$(stat -Lc %U:%a ${config.age.secrets.owned.path})" = reader:400
      '';
    };
  };
in
pkgs.testers.nixosTest {
  name = "agenix-native-init";
  nodes.early = makeNode false;
  nodes.late = makeNode true;
  testScript = ''
    for machine in [early, late]:
        machine.wait_for_unit("multi-user.target")
        machine.succeed("systemctl is-active userborn.service")
        machine.succeed("systemctl is-active agenix-install-secrets.service")
        machine.succeed("systemctl is-active secret-consumer.service")
        machine.succeed("test $(stat -Lc %U:%a /run/agenix/owned) = reader:400")
        if machine is early:
            machine.succeed("systemctl is-active agenix-chown.service")
            machine.succeed('test "$(getent shadow reader | cut -d: -f2)" = "$(cat /run/agenix/password)"')
        # A fresh boot must recreate plaintext, without an earlier activation.
        machine.shutdown()
        machine.wait_for_unit("multi-user.target")
        machine.succeed("systemctl is-active secret-consumer.service")
        machine.succeed("test $(stat -Lc %U:%a /run/agenix/owned) = reader:400")
        machine.shutdown()
  '';
}
