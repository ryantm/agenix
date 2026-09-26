{ pkgs }:
pkgs.nixosTest {
  name = "agenix-parallel-decryption";

  nodes.machine =
    { config, pkgs, ... }:
    let
      ageWithBarrier = pkgs.writeShellScript "age-with-barrier" ''
        if [ -d /tmp/agenix-decryption-barrier ]; then
          touch "/tmp/agenix-decryption-barrier/started.$BASHPID"
          for attempt in {1..100}; do
            started=(/tmp/agenix-decryption-barrier/started.*)
            if [ "''${#started[@]}" -ge 2 ]; then
              break
            fi
            sleep 0.1
          done
          if [ "''${#started[@]}" -lt 2 ]; then
            echo "decryptions did not overlap" >&2
            exit 1
          fi
        fi
        # Model the switch environment from issue #355: background age has no
        # controlling terminal even though the activation itself does.
        if [ -e /run/agenix-test/passkey ] && [ ! -t 0 ]; then
          exec ${pkgs.util-linux}/bin/setsid ${pkgs.age}/bin/age "$@"
        fi
        exec ${pkgs.age}/bin/age "$@"
      '';
      activateSecrets = pkgs.writeShellScriptBin "activate-test-secrets" ''
        set -e
        ${config.system.activationScripts.agenixNewGeneration.text}
        ${config.system.activationScripts.agenixInstall.text}
      '';
    in
    {
      imports = [ ../modules/age.nix ];

      systemd.sysusers.enable = false;
      age.ageBin = "${ageWithBarrier}";
      age.identityPaths = [
        "/run/agenix-test/system1"
        "/run/agenix-test/passkey"
      ];
      age.secrets.a.file = ../example/secret1.age;
      age.secrets.b.file = "/run/agenix-test/b.age";

      system.activationScripts.agenixTestFixtures = {
        deps = [ "specialfs" ];
        text = ''
          mkdir -p /run/agenix-test
          install -m 0600 ${../example_keys/system1} /run/agenix-test/system1
          cp ${../example/secret1.age} /run/agenix-test/b.age
        '';
      };
      system.activationScripts.agenixInstall.deps = [ "agenixTestFixtures" ];

      environment.systemPackages = [
        pkgs.age
        pkgs.openssh
        pkgs.util-linux
        activateSecrets
      ];
    };

  testScript = ''
    machine.wait_for_unit("multi-user.target")
    assert machine.succeed("systemctl is-active multi-user.target").strip() == "active"
    assert machine.succeed("readlink /run/agenix").strip() == "/run/agenix.d/1"
    assert machine.succeed("cat /run/agenix/a").strip() == "hello"
    assert machine.succeed("cat /run/agenix/b").strip() == "hello"

    # The barrier fails if the second age process never starts.
    machine.succeed("mkdir /tmp/agenix-decryption-barrier")
    machine.succeed("timeout 30s activate-test-secrets < /dev/null")
    machine.succeed("test $(find /tmp/agenix-decryption-barrier -name 'started.*' | wc -l) -eq 2")
    machine.succeed("rm -rf /tmp/agenix-decryption-barrier")

    # An interactive switch without encrypted identities can also stay parallel.
    machine.succeed("mkdir /tmp/agenix-decryption-barrier")
    status, output = machine.execute("timeout 30s script -q -e -c 'activate-test-secrets' /dev/null < /dev/null")
    assert status == 0, output
    machine.succeed("test $(find /tmp/agenix-decryption-barrier -name 'started.*' | wc -l) -eq 2")
    machine.succeed("rm -rf /tmp/agenix-decryption-barrier")

    # Replace one ciphertext with one encrypted for a passphrase-protected SSH key.
    machine.succeed("ssh-keygen -q -t ed25519 -N test-passphrase -f /run/agenix-test/passkey")
    machine.succeed("printf 'passphrase-secret' | age --encrypt -R /run/agenix-test/passkey.pub -o /run/agenix-test/b.age")

    # script gives the activation a controlling terminal, as nixos-rebuild switch does.
    status, output = machine.execute("printf 'test-passphrase\\n' | timeout 30s script -q -e -c 'activate-test-secrets' /dev/null")
    assert status == 0, output
    assert "Enter passphrase" in output, output
    assert machine.succeed("cat /run/agenix/b").strip() == "passphrase-secret"
  '';
}
