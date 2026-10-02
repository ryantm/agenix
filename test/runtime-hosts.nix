{ pkgs }:
let
  # Public fixture contents, encrypted only to exercise the runtime integration.
  hosts =
    address:
    pkgs.runCommand "agenix-hosts.age" { nativeBuildInputs = [ pkgs.age ]; } ''
      cat <<EOF | age -R ${../example_keys/system1.pub} -o "$out"
      127.0.0.1 localhost
      ::1 localhost
      127.0.0.2 machine
      ${address} private.example.test
      EOF
    '';
  first = hosts "192.0.2.1";
  second = hosts "192.0.2.2";
in
pkgs.testers.nixosTest {
  name = "agenix-runtime-hosts";
  nodes.machine = { config, lib, ... }: {
    imports = [ ../modules/age.nix ];
    users.users.alice.isNormalUser = true;
    # This is the repository's public test identity.
    age.identityPaths = [ "${../example_keys/system1}" ];
    age.secrets.hosts = {
      file = "/var/lib/agenix-test-hosts.age";
      mode = "0444";
    };
    environment.etc.hosts.source = lib.mkForce config.age.secrets.hosts.path;
    system.activationScripts.prepareTestHosts = {
      deps = [ "specialfs" ];
      text = ''
        if [ ! -e /var/lib/agenix-test-hosts.age ]; then
          install -Dm600 ${first} /var/lib/agenix-test-hosts.age
        fi
      '';
    };
    system.activationScripts.agenixInstall.deps = [ "prepareTestHosts" ];
  };
  testScript = ''
    machine.wait_for_unit("multi-user.target")

    with subtest("The runtime hosts file is available to ordinary users"):
        assert "192.0.2.1" in machine.succeed("runuser -u alice -- getent hosts private.example.test")
        machine.succeed("runuser -u alice -- getent hosts localhost")
        assert machine.succeed("hostname -f").strip() == "machine"
        machine.succeed("test $(stat -Lc %U:%a /etc/hosts) = root:444")
        assert machine.succeed("readlink -f /etc/hosts").strip() == "/run/agenix.d/1/hosts"

    with subtest("Activating new ciphertext replaces the hosts generation"):
        machine.succeed("install -m600 ${second} /var/lib/agenix-test-hosts.age")
        machine.succeed("/run/current-system/activate")
        assert "192.0.2.2" in machine.succeed("runuser -u alice -- getent -s files hosts private.example.test")
        assert machine.succeed("readlink -f /etc/hosts").strip() == "/run/agenix.d/2/hosts"
        machine.succeed("test ! -e /run/agenix.d/1")
  '';
}
