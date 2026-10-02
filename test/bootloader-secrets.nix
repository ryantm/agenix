{ pkgs }:
let
  lib = pkgs.lib;
  fixtures =
    pkgs.runCommand "agenix-bootloader-public-fixtures"
      {
        nativeBuildInputs = [
          pkgs.age
          pkgs.grub2
        ];
      }
      ''
        mkdir "$out"
        # All inputs here are public fixtures. Never put real keys/hashes in a build.
        printf 'test-password\ntest-password\n' | grub-mkpasswd-pbkdf2 -c 1000 |
          sed -n 's/.*\(grub.pbkdf2.*\)/\1/p' > "$out/grub-hash"
        test -s "$out/grub-hash"
        age -R ${../example_keys/system1.pub} -o "$out/grub.age" "$out/grub-hash"
        age -R ${../example_keys/system1.pub} -o "$out/first.age" ${../example_keys/user1}
        age -R ${../example_keys/system1.pub} -o "$out/second.age" ${../example_keys/system1}
      '';
in
pkgs.testers.nixosTest {
  name = "agenix-bootloader-secrets";
  nodes.machine =
    { config, ... }:
    {
      imports = [ ../modules/age-bootloader.nix ];
      virtualisation.useBootLoader = true;
      virtualisation.additionalPaths = [
        ../example_keys/user1
        fixtures
      ];
      boot.loader.grub.device = "/dev/vda";
      boot.loader.grub.users.test.hashedPasswordFile = config.age.bootloaderSecrets.grub.path;
      boot.initrd.systemd.enable = true;
      boot.initrd.network.enable = true;
      boot.initrd.network.ssh = {
        enable = true;
        hostKeys = [ config.age.bootloaderSecrets.ssh.path ];
        authorizedKeys = [ (builtins.readFile ../example_keys/user1.pub) ];
      };
      # Public fixture available even before the first activation.
      age.identityPaths = [ "${../example_keys/system1}" ];
      age.ageBin = toString (
        pkgs.writeShellScript "bootloader-test-age" ''
          if test -e /run/agenix-test-fail; then
            for argument in "$@"; do
              if test "''${argument##*/}" = ssh; then
                echo 'deliberate decryption failure after the first secret' >&2
                exit 42
              fi
            done
          fi
          exec ${pkgs.age}/bin/age "$@"
        ''
      );
      age.bootloaderSecrets = {
        grub.file = "${fixtures}/grub.age";
        ssh.file = "${fixtures}/first.age";
        disabled.enable = false;
      };
      age.secrets.normal.file = ../example/secret1.age;
      specialisation.updated.configuration = {
        age.bootloaderSecrets.ssh.file = lib.mkForce "${fixtures}/second.age";
      };
      specialisation.missing.configuration = {
        age.identityPaths = lib.mkForce [ "/etc/agenix-absent-key" ];
      };
      specialisation.failedInstaller.configuration = {
        system.build.installBootLoader = lib.mkForce (
          pkgs.writeShellScript "failing-bootloader" ''
            test "$(stat -c %u:%g:%a /run/agenix-bootloader/grub)" = 0:0:400 || exit 24
            test -s /run/agenix-bootloader/ssh || exit 24
            echo 'fixture reached protected inputs' >&2
            exit 23
          ''
        );
      };
      environment.systemPackages = [ pkgs.openssh ];
    };

  testScript = ''
    machine.wait_for_unit("multi-user.target")
    first = machine.succeed("readlink -f /run/current-system").strip()
    updated = first + "/specialisation/updated"
    missing = first + "/specialisation/missing"
    failed_installer = first + "/specialisation/failedInstaller"

    with subtest("Initial boot reads the SSH key appended by the wrapped installer"):
        machine.succeed("cmp /run/agenix-bootloader/ssh ${../example_keys/user1}")
        machine.succeed("grep -Ff ${fixtures}/grub-hash /boot/grub/grub.cfg")
        generation = machine.succeed("readlink /run/agenix").strip()
        machine.succeed("cp /boot/grub/grub.cfg /root/grub-before")

    with subtest("Failure stops before installing bootloader files"):
        machine.succeed("touch /run/agenix-test-fail")
        machine.fail(updated + "/bin/switch-to-configuration boot")
        machine.succeed("cmp /boot/grub/grub.cfg /root/grub-before")
        machine.succeed("test -z \"$(find /run/agenix-bootloader -name '.stage.*' -print)\"")
        machine.succeed("rm /run/agenix-test-fail")
        machine.fail(missing + "/bin/switch-to-configuration boot")
        machine.succeed("cmp /boot/grub/grub.cfg /root/grub-before")

    with subtest("A failing installer also removes its plaintext inputs"):
        output = machine.fail(failed_installer + "/bin/switch-to-configuration boot 2>&1")
        assert "fixture reached protected inputs" in output, output
        machine.succeed("cmp /boot/grub/grub.cfg /root/grub-before")
        machine.succeed("test ! -e /run/agenix-bootloader/ssh; test ! -e /run/agenix-bootloader/grub")

    with subtest("Boot-only update prepares secrets without normal activation"):
        machine.succeed(updated + "/bin/switch-to-configuration boot")
        assert machine.succeed("readlink /run/agenix").strip() == generation
        assert machine.succeed("readlink -f /run/current-system").strip() == first
        machine.succeed("test ! -e /run/agenix-bootloader/ssh; test ! -e /run/agenix-bootloader/grub")
        machine.succeed("test \"$(stat -c %a /run/agenix-bootloader)\" = 700")
        machine.succeed("test -z \"$(find /run/agenix-bootloader -name '.stage.*' -print)\"")
        # The test harness does not update the system profile for direct calls.
        machine.succeed("grub-set-default 0")
        machine.shutdown()

    with subtest("The next boot uses the replacement initrd SSH key"):
        machine.wait_for_unit("multi-user.target")
        machine.succeed("cmp /run/agenix-bootloader/ssh ${../example_keys/system1}")
        machine.succeed("test -L /run/agenix; test -f /run/agenix/normal")
        machine.succeed("test ! -L /run/agenix-bootloader")
  '';
}
