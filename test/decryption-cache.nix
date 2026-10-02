{ pkgs }:
let
  makeNode = sysusers: { config, lib, ... }: {
    imports = [ ../modules/age.nix ];
    systemd.sysusers.enable = sysusers;
    services.userborn.enable = false;
    age.ageBin = "${pkgs.writeShellScript "count-age" ''
      echo decrypt >> /run/agenix-cache-test/calls
      if test -e /run/agenix-cache-test/mutate; then
        cp ${../example/-leading-hyphen-filename.age} /run/agenix-cache-test/secret.age
        rm /run/agenix-cache-test/mutate
      fi
      exec ${pkgs.age}/bin/age "$@"
    ''}";
    age.identityPaths = [
      "/run/agenix-cache-test/key"
      "/run/agenix-cache-test/optional-key"
    ];
    age.secrets = {
      normal.file = "/run/agenix-cache-test/secret.age";
      linked = {
        file = ../example/secret1.age;
        path = "/var/lib/cache-linked";
      };
      direct = {
        file = ../example/secret1.age;
        path = "/var/lib/cache-direct";
        symlink = false;
      };
    };
    age.derivedSecrets.rendered = {
      template = "/run/agenix-cache-test/template";
      secrets = [ config.age.secrets.normal ];
    };
    system.activationScripts.cacheFixtures.text = ''
      mkdir -p /run/agenix-cache-test
      if ! test -e /run/agenix-cache-test/key; then
        install -m 0600 ${../example_keys/system1} /run/agenix-cache-test/key
      fi
      if ! test -e /run/agenix-cache-test/secret.age; then
        cp ${../example/secret1.age} /run/agenix-cache-test/secret.age
      fi
      if ! test -e /run/agenix-cache-test/template; then
        printf 'value=@normal@' > /run/agenix-cache-test/template
      fi
    '';
    system.activationScripts.agenixInstall = lib.mkIf (!sysusers) { deps = [ "cacheFixtures" ]; };
    specialisation.uncached.configuration.age.cacheDecryption = false;
    specialisation.permissions.configuration.age.secrets.normal.mode = lib.mkForce "0440";
  };
in
pkgs.testers.nixosTest {
  name = "agenix-decryption-cache";
  nodes.activation = makeNode false;
  nodes.sysusers = makeNode true;
  testScript = ''
    for machine in [activation, sysusers]:
        machine.start()
        machine.wait_for_unit("multi-user.target")
        system = machine.succeed("readlink -f /run/current-system").strip()
        # This test deliberately restarts faster than systemd's rate limit.
        command = "systemctl reset-failed agenix-install-secrets.service agenix-chown.service && systemctl restart agenix-install-secrets.service && systemctl start agenix-chown.service" if machine == sysusers else "/run/current-system/activate"
        def generation():
            return machine.succeed("readlink /run/agenix").strip()
        def calls():
            return int(machine.succeed("wc -l < /run/agenix-cache-test/calls"))
        def cached():
            old, count = generation(), calls()
            inodes = machine.succeed("stat -Lc %i /run/agenix/normal /var/lib/cache-linked /var/lib/cache-direct /run/agenix/rendered")
            machine.succeed(command)
            assert generation() == old
            assert calls() == count
            assert machine.succeed("stat -Lc %i /run/agenix/normal /var/lib/cache-linked /var/lib/cache-direct /run/agenix/rendered") == inodes
        def renewed():
            old, count = generation(), calls()
            machine.succeed(command)
            assert generation() != old
            assert calls() == count + 3
            machine.succeed("test ! -e " + old)
            cached()

        cached()
        cached()
        current = generation().split("/")[-1]
        assert machine.succeed("stat -c %a /run/agenix.d/.cache-" + current).strip() == "700"
        assert machine.succeed("stat -c %a /run/agenix.d/.cache-" + current + "/outputs").strip() == "600"

        # Runtime ciphertext changes and re-encryption must invalidate the cache.
        machine.succeed("cp ${../example/secret1-copy.age} /run/agenix-cache-test/secret.age")
        renewed()
        machine.succeed("cp ${../example/-leading-hyphen-filename.age} /run/agenix-cache-test/secret.age")
        renewed()
        assert machine.succeed("cat /run/agenix/rendered") == "value=filename started with hyphen"

        # Missing output, modified plaintext, permissions, and wrong symlinks.
        machine.succeed("rm /run/agenix/normal")
        renewed()
        machine.succeed("printf changed > /var/lib/cache-direct")
        renewed()
        assert machine.succeed("cat /var/lib/cache-direct").strip() == "hello"
        machine.succeed("chmod 0600 /run/agenix/normal")
        renewed()
        assert machine.succeed("stat -Lc %a /run/agenix/normal").strip() == "400"
        machine.succeed("ln -sf /var/lib/cache-direct /var/lib/cache-linked")
        renewed()
        assert machine.succeed("readlink /var/lib/cache-linked").strip() == "/run/agenix/linked"

        machine.succeed("printf 'updated=@normal@' > /run/agenix-cache-test/template")
        renewed()
        assert machine.succeed("cat /run/agenix/rendered") == "updated=filename started with hyphen"
        machine.succeed("printf '\\n' >> /run/agenix-cache-test/key")
        renewed()
        machine.succeed("cp /run/agenix-cache-test/key /run/agenix-cache-test/optional-key")
        renewed()
        machine.succeed("rm /run/agenix-cache-test/optional-key")
        renewed()

        old = generation()
        machine.succeed("printf invalid > /run/agenix-cache-test/secret.age")
        machine.fail(command)
        assert generation() == old
        machine.succeed("test ! -e " + old.replace("/agenix.d/", "/agenix.d/.backup-"))
        machine.succeed("cp ${../example/secret1.age} /run/agenix-cache-test/secret.age")
        renewed()
        assert machine.succeed("cat /run/agenix/normal").strip() == "hello"

        # Inputs changing during decryption cannot become a reusable cache.
        machine.succeed("touch /run/agenix-cache-test/mutate && chmod 0600 /run/agenix/normal")
        machine.succeed(command)
        current = generation().split("/")[-1]
        machine.fail("test -d /run/agenix.d/.cache-" + current)
        renewed()

        old, count = generation(), calls()
        machine.succeed(system + "/specialisation/permissions/bin/switch-to-configuration test")
        assert generation() != old and calls() > count
        assert machine.succeed("stat -Lc %a /run/agenix/normal").strip() == "440"

        machine.succeed(system + "/specialisation/uncached/bin/switch-to-configuration test")
        for _ in range(2):
            old, count = generation(), calls()
            machine.succeed(command)
            assert generation() != old and calls() == count + 3
        machine.shutdown()
  '';
}
