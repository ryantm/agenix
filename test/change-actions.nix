{ pkgs }:
let
  names = [
    "unchanged"
    "reencrypted"
    "content"
    "custom"
    "path"
    "direct-path"
    "mode"
    "owner"
    "symlink-on"
    "symlink-off"
    "added"
    "a-dynamic"
    "z-dynamic"
  ];
  makeNode =
    sysusers:
    {
      config,
      lib,
      pkgs,
      ...
    }:
    {
      imports = [
        ../modules/age.nix
        {
          age.secrets = lib.genAttrs names (name: {
            file = ../example/secret1.age;
            onChange = "touch /tmp/${name}-hook";
            reloadUnits = [ "${name}-reload.service" ];
            restartUnits = [ "${name}-restart.service" ];
          });
        }
      ];
      systemd.sysusers.enable = sysusers;
      services.userborn.enable = false;
      users.users.secret-owner = {
        isSystemUser = true;
        group = "users";
      };
      age.identityPaths = [ "${../example_keys/system1}" ];
      age.secrets.added.enable = false;
      age.secrets.custom.path = "/var/lib/agenix-test/custom";
      age.secrets.direct-path = {
        path = "/var/lib/agenix-test/direct";
        symlink = false;
      };
      age.secrets.symlink-on.symlink = false;
      age.secrets.a-dynamic.file = lib.mkForce "/run/agenix-test/a.age";
      age.secrets.z-dynamic.file = lib.mkForce "/run/agenix-test/z.age";
      system.activationScripts.agenixTestFixtures.text = ''
        mkdir -p /run/agenix-test
        for name in a z; do
          if ! test -e "/run/agenix-test/$name.age"; then
            cp ${../example/secret1.age} "/run/agenix-test/$name.age"
          fi
        done
      '';
      system.activationScripts.agenixInstall = lib.mkIf (!sysusers) {
        deps = [ "agenixTestFixtures" ];
      };
      systemd.services = lib.listToAttrs (
        lib.concatMap (name: [
          {
            name = "${name}-reload";
            value = {
              wantedBy = [ "multi-user.target" ];
              serviceConfig = {
                Type = "oneshot";
                RemainAfterExit = true;
              };
              script = "true";
              reload = "touch /tmp/${name}-reloaded";
            };
          }
          {
            name = "${name}-restart";
            value = {
              wantedBy = [ "multi-user.target" ];
              serviceConfig = {
                Type = "oneshot";
                RemainAfterExit = true;
              };
              script = "true";
              preStop = "touch /tmp/${name}-restarted";
            };
          }
        ]) names
      );
      specialisation.updated.configuration = {
        age.secrets = {
          reencrypted.file = lib.mkForce ../example/secret1-copy.age;
          content = {
            file = lib.mkForce ../example/passwordfile-user1.age;
            onChange = lib.mkForce "touch /tmp/content-new-hook";
          };
          custom.file = lib.mkForce ../example/passwordfile-user1.age;
          path.path = lib.mkForce "/var/lib/agenix-test/moved";
          direct-path.path = lib.mkForce "/var/lib/agenix-test/direct-moved";
          mode.mode = lib.mkForce "0440";
          owner.owner = lib.mkForce "secret-owner";
          symlink-on.symlink = lib.mkForce true;
          symlink-off.symlink = lib.mkForce false;
          added.enable = lib.mkForce true;
        };
      };
    };
in
pkgs.testers.nixosTest {
  name = "agenix-change-actions";
  nodes.activation = makeNode false;
  nodes.sysusers = makeNode true;
  testScript = ''
    names = ${builtins.toJSON names}
    changed = ["content", "custom", "path", "direct-path", "mode", "owner", "added"]
    for machine in [activation, sysusers]:
        machine.start()
        machine.wait_for_unit("multi-user.target")
        machine.succeed("test -f /run/agenix/unchanged")
        for name in names:
            machine.wait_for_unit(name + "-reload.service")
            machine.wait_for_unit(name + "-restart.service")
            machine.fail("test -f /tmp/" + name + "-hook")
            machine.fail("test -f /tmp/" + name + "-reloaded")
            machine.fail("test -f /tmp/" + name + "-restarted")

        machine.succeed("/run/current-system/specialisation/updated/bin/switch-to-configuration test")
        for name in changed:
            hook = "content-new" if name == "content" else name
            machine.wait_for_file("/tmp/" + hook + "-hook")
            machine.wait_for_file("/tmp/" + name + "-reloaded")
            machine.wait_for_file("/tmp/" + name + "-restarted")
        machine.fail("test -f /tmp/content-hook")
        for name in set(names) - set(changed):
            machine.fail("test -f /tmp/" + name + "-hook")
            machine.fail("test -f /tmp/" + name + "-reloaded")
            machine.fail("test -f /tmp/" + name + "-restarted")

        # A changed plaintext staged before a later failure must not notify.
        generation = machine.succeed("readlink /run/agenix").strip()
        machine.succeed("cp ${../example/passwordfile-user1.age} /run/agenix-test/a.age")
        machine.succeed("printf invalid > /run/agenix-test/z.age")
        command = "systemctl restart agenix-install-secrets.service" if machine == sysusers else "/run/current-system/activate"
        machine.fail(command)
        assert machine.succeed("readlink /run/agenix").strip() == generation
        assert machine.succeed("cat /run/agenix/a-dynamic").strip() == "hello"
        machine.fail("test -f /tmp/a-dynamic-hook")
        machine.fail("test -f /tmp/a-dynamic-reloaded")
        machine.fail("test -f /tmp/a-dynamic-restarted")
        machine.succeed("cp ${../example/secret1.age} /run/agenix-test/z.age")
        machine.succeed(command)
        if machine == sysusers:
            machine.succeed("systemctl start agenix-chown.service")
        machine.wait_for_file("/tmp/a-dynamic-hook")
        machine.wait_for_file("/tmp/a-dynamic-reloaded")
        machine.wait_for_file("/tmp/a-dynamic-restarted")
        machine.shutdown()
  '';
}
