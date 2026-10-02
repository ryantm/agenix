{ pkgs }:
let
  richText = pkgs.writeText "template-test-secret" ''
    literal $(touch /tmp/agenix-template-pwned) `commands` \ "quotes" 'apostrophe' @plain@
    second line
  '';
  richCipher = pkgs.runCommand "template-test-secret.age" { } ''
    ${pkgs.age}/bin/age -R ${../example_keys/system1.pub} -o "$out" < ${richText}
  '';
  publicTemplate = pkgs.writeText "template-test-config" ''
    plain=@plain@
    rich=@regex[.*]@
  '';
  makeNode = sysusers: { config, lib, ... }: {
    imports = [ ../modules/age.nix ];
    systemd.sysusers.enable = sysusers;
    services.userborn.enable = false;
    users.users.template-owner = {
      isSystemUser = true;
      group = "users";
    };
    age.identityPaths = [ "${../example_keys/system1}" ];
    age.secrets = {
      plain = {
        file = ../example/secret1.age;
        path = "/var/lib/agenix-plain";
        symlink = false;
      };
      rich = {
        file = richCipher;
        name = "regex[.*]";
      };
    };
    age.derivedSecrets = {
      a-config = {
        template = "/run/agenix-test/config.template";
        secrets = with config.age.secrets; [
          plain
          rich
        ];
        owner = "template-owner";
        mode = "0440";
        onChange = "touch /tmp/template-hook";
      };
      exact = {
        template = pkgs.writeText "exact-template" "@regex[.*]@";
        secrets = [ config.age.secrets.rich ];
        trimFinalNewline = false;
        path = "/var/lib/agenix-exact";
        symlink = false;
      };
      z-fails = {
        template = "/run/agenix-test/failable.template";
        secrets = [ config.age.secrets.plain ];
      };
      disabled.enable = false;
      literal-path = {
        template = ./fixtures/template.txt;
        secrets = [ config.age.secrets.plain ];
      };
    };
    system.activationScripts.templateTestFixtures.text = ''
      mkdir -p /run/agenix-test
      for name in config failable; do
        if ! test -e "/run/agenix-test/$name.template"; then
          cp ${publicTemplate} "/run/agenix-test/$name.template"
        fi
      done
    '';
    system.activationScripts.agenixInstall = lib.mkIf (!sysusers) {
      deps = [ "templateTestFixtures" ];
    };
  };
in
pkgs.testers.nixosTest {
  name = "agenix-templates";
  nodes.activation = makeNode false;
  nodes.sysusers = makeNode true;
  testScript = ''
    for machine in [activation, sysusers]:
        machine.start()
        machine.wait_for_unit("multi-user.target")
        expected = "plain=hello\nrich=" + machine.succeed("cat ${richText}")
        assert machine.succeed("cat /run/agenix/a-config") == expected
        machine.succeed("cmp ${richText} /var/lib/agenix-exact")
        assert machine.succeed("cat /run/agenix/literal-path") == "literal=hello\n"
        assert machine.succeed("stat -Lc %U:%G:%a /run/agenix/a-config").strip() == "template-owner:users:440"
        machine.fail("test -e /run/agenix/disabled")
        machine.fail("test -e /tmp/agenix-template-pwned")
        machine.fail("test -e /tmp/template-hook")
        command = "systemctl restart agenix-install-secrets.service" if machine == sysusers else "/run/current-system/activate"
        machine.succeed(command)
        machine.fail("test -e /tmp/template-hook")

        generation = machine.succeed("readlink /run/agenix").strip()
        machine.succeed("printf 'updated:@plain@' > /run/agenix-test/config.template")
        machine.succeed("rm /run/agenix-test/failable.template && mkdir /run/agenix-test/failable.template")
        machine.fail(command)
        assert machine.succeed("readlink /run/agenix").strip() == generation
        assert machine.succeed("cat /run/agenix/a-config") == expected
        machine.fail("test -e /tmp/template-hook")
        machine.succeed("rmdir /run/agenix-test/failable.template && cp ${publicTemplate} /run/agenix-test/failable.template")
        machine.succeed(command)
        if machine == sysusers:
            machine.succeed("systemctl start agenix-chown.service")
        machine.wait_for_file("/tmp/template-hook")
        assert machine.succeed("cat /run/agenix/a-config") == "updated:hello"
        machine.shutdown()
  '';
}
