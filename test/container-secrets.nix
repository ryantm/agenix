{ pkgs }:
pkgs.testers.nixosTest {
  name = "agenix-container-secrets";
  nodes.machine = {
    imports = [ ../modules/age.nix ];
    # Public repository fixture, used only by this test's host.
    age.identityPaths = [ "${../example_keys/user1}" ];
    age.secrets = {
      demo-token = {
        file = "/var/lib/agenix-container-test.age";
        path = "/run/agenix-containers/demo/token";
        symlink = false;
      };
      unrelated.file = ../example/secret1.age;
    };
    systemd.tmpfiles.rules = [ "d /run/agenix-containers/demo 0700 root root -" ];
    system.activationScripts.prepareContainerTestSecret = {
      deps = [ "specialfs" ];
      text = ''
        if [ ! -e /var/lib/agenix-container-test.age ]; then
          install -Dm600 ${../example/secret1.age} /var/lib/agenix-container-test.age
        fi
      '';
    };
    system.activationScripts.agenixInstall.deps = [ "prepareContainerTestSecret" ];
    containers.demo = {
      autoStart = true;
      bindMounts."/run/secrets" = {
        hostPath = "/run/agenix-containers/demo";
        isReadOnly = true;
      };
      config = {
        system.stateVersion = "26.05";
      };
    };
  };
  testScript = ''
    machine.wait_for_unit("multi-user.target")
    machine.wait_for_unit("container@demo.service")
    machine.wait_until_succeeds("nixos-container run demo -- test -f /run/secrets/token")

    with subtest("The container receives only its plaintext secret and a read-only mount"):
        assert machine.succeed("nixos-container run demo -- cat /run/secrets/token") == "hello\n"
        machine.succeed("nixos-container run demo -- test ! -L /run/secrets/token")
        machine.succeed("nixos-container run demo -- test ! -e /run/agenix/unrelated")
        machine.succeed("nixos-container run demo -- test ! -e /etc/ssh/ssh_host_ed25519_key")
        machine.fail("nixos-container run demo -- sh -c 'printf changed >> /run/secrets/token'")
        pid = machine.succeed("systemctl show container@demo.service -p MainPID --value")
        directory_inode = machine.succeed("stat -c %i /run/agenix-containers/demo")

    with subtest("The running container sees replacements after generation cleanup"):
        machine.succeed("install -m600 ${../example/secret2.age} /var/lib/agenix-container-test.age")
        machine.succeed("/run/current-system/activate")
        machine.succeed("test ! -e /run/agenix.d/1")
        assert machine.succeed("nixos-container run demo -- cat /run/secrets/token") == "world!\n"
        assert machine.succeed("systemctl show container@demo.service -p MainPID --value") == pid
        assert machine.succeed("stat -c %i /run/agenix-containers/demo") == directory_inode
        machine.fail("nixos-container run demo -- sh -c 'printf changed >> /run/secrets/token'")
  '';
}
