{
  pkgs,
}:
pkgs.testers.nixosTest {
  name = "agenix-failure-safety";

  nodes.machine =
    { pkgs, ... }:
    {
      imports = [ ../modules/age.nix ];

      systemd.sysusers.enable = true;
      age.identityPaths = [ "${../example_keys/system1}" ];
      age.secrets.a-direct = {
        file = "/etc/agenix-test/direct.age";
        path = "/run/agenix-direct";
        symlink = false;
      };
      age.secrets.bad.file = "/etc/agenix-test/bad.age";
      age.secrets.good = {
        file = ../example/secret1.age;
        owner = "agenix-reader";
        group = "users";
      };
      age.secrets.direct-default = {
        file = ../example/secret1.age;
        symlink = false;
      };
      users.users.agenix-reader = {
        isSystemUser = true;
        group = "users";
      };
      environment.etc."agenix-test/bad.age".source = pkgs.writeText "invalid.age" "invalid ciphertext";
      environment.etc."agenix-test/direct.age".source = ../example/secret1.age;

      environment.systemPackages = [
        (pkgs.callPackage ../pkgs/agenix.nix { })
        pkgs.util-linux
      ];
    };

  nodes.activation = { pkgs, ... }: {
    imports = [ ../modules/age.nix ];
    systemd.sysusers.enable = false;
    services.userborn.enable = false;
    age.identityPaths = [ "${../example_keys/system1}" ];
    age.secrets.a-direct = {
      file = "/etc/agenix-test/direct.age";
      path = "/run/agenix-direct";
      symlink = false;
    };
    age.secrets.bad.file = "/etc/agenix-test/bad.age";
    system.activationScripts.agenixInstall.deps = [ "agenixTestFixture" ];
    system.activationScripts.agenixTestFixture.text = ''
      mkdir -p /etc/agenix-test
      for name in bad direct; do
        if ! test -e "/etc/agenix-test/$name.age"; then
          cp ${../example/secret1.age} "/etc/agenix-test/$name.age"
        fi
      done
    '';
  };

  testScript = ''
    machine.start()
    machine.wait_for_unit("multi-user.target")
    assert machine.succeed("systemctl is-active multi-user.target").strip() == "active"
    assert machine.succeed("systemctl is-failed agenix-install-secrets.service").strip() == "failed"
    machine.fail("readlink /run/agenix")
    machine.succeed("test ! -e /run/agenix-direct")

    machine.succeed("rm /etc/agenix-test/bad.age")
    machine.succeed("cp ${../example/secret1.age} /etc/agenix-test/bad.age")
    machine.succeed("systemctl reset-failed agenix-install-secrets.service")
    machine.succeed("systemctl start agenix-install-secrets.service")
    machine.succeed("systemctl start agenix-chown.service")
    generation = machine.succeed("readlink /run/agenix").strip()
    assert generation == "/run/agenix.d/1"
    assert machine.succeed("cat /run/agenix/bad").strip() == "hello"
    assert machine.succeed("cat /run/agenix/good").strip() == "hello"
    assert machine.succeed("cat /run/agenix-direct").strip() == "hello"
    assert machine.succeed("cat /run/agenix/direct-default").strip() == "hello"
    assert machine.succeed("stat -Lc %U /run/agenix/good").strip() == "agenix-reader"
    machine.succeed("test ! -e /run/agenix/a-direct")

    machine.succeed("rm /etc/agenix-test/direct.age")
    machine.succeed("cp ${../example/-leading-hyphen-filename.age} /etc/agenix-test/direct.age")
    machine.succeed("printf invalid > /etc/agenix-test/bad.age")
    machine.fail("systemctl restart agenix-install-secrets.service")
    assert machine.succeed("readlink /run/agenix").strip() == generation
    assert machine.succeed("cat /run/agenix/bad").strip() == "hello"
    assert machine.succeed("cat /run/agenix/good").strip() == "hello"
    assert machine.succeed("cat /run/agenix-direct").strip() == "hello"
    machine.succeed("test -e /run/agenix.d/1/bad")
    assert machine.succeed("systemctl is-active multi-user.target").strip() == "active"

    machine.succeed("cp ${../example/secret1.age} /etc/agenix-test/bad.age")
    machine.succeed("systemctl reset-failed agenix-install-secrets.service")
    machine.succeed("systemctl start agenix-install-secrets.service")
    machine.succeed("systemctl start agenix-chown.service")
    assert machine.succeed("readlink /run/agenix").strip() == "/run/agenix.d/2"
    assert machine.succeed("cat /run/agenix/bad").strip() == "hello"
    assert machine.succeed("cat /run/agenix-direct").strip() == "filename started with hyphen"
    machine.succeed("test ! -e /run/agenix.d/1/bad")

    # Ownership is assigned after sysusers. If that step fails, restore both
    # the generation link and direct-path contents, then allow a fresh retry.
    machine.succeed("systemctl stop agenix-chown.service agenix-install-secrets.service")
    machine.succeed("userdel agenix-reader")
    machine.succeed("cp ${../example/secret1.age} /etc/agenix-test/direct.age")
    machine.succeed("systemctl start agenix-install-secrets.service")
    machine.fail("systemctl start agenix-chown.service")
    assert machine.succeed("readlink /run/agenix").strip() == "/run/agenix.d/2"
    assert machine.succeed("cat /run/agenix-direct").strip() == "filename started with hyphen"
    assert machine.succeed("cat /run/agenix/good").strip() == "hello"
    machine.succeed("test ! -e /run/agenix.d/3")
    machine.succeed("useradd --system -g users agenix-reader")
    machine.succeed("systemctl restart agenix-install-secrets.service")
    machine.succeed("systemctl start agenix-chown.service")
    assert machine.succeed("readlink /run/agenix").strip() == "/run/agenix.d/3"
    assert machine.succeed("cat /run/agenix-direct").strip() == "hello"
    assert machine.succeed("stat -Lc %U /run/agenix/good").strip() == "agenix-reader"
    machine.succeed("test ! -e /run/agenix.d/.backup-3")

    machine.succeed("mkdir -p /tmp/agenix-home/.ssh /tmp/agenix-secrets")
    machine.succeed("cp ${../example_keys/user1} /tmp/agenix-home/.ssh/id_ed25519")
    machine.succeed("chmod 600 /tmp/agenix-home/.ssh/id_ed25519")
    machine.succeed("cp ${../example/agenix-rules.nix} /tmp/agenix-secrets/agenix-rules.nix")
    machine.succeed("cp ${../example}/*.age /tmp/agenix-secrets/")
    machine.succeed("mv /tmp/agenix-secrets/secret1.age /tmp/agenix-secrets/secret1.age.hidden")
    cli = "cd /tmp/agenix-secrets && HOME=/tmp/agenix-home agenix"
    machine.fail(cli + " -d secret1.age")
    machine.fail(cli + " -r -i /tmp/agenix-home/.ssh/id_ed25519")
    machine.succeed("test ! -e /tmp/agenix-secrets/secret1.age")

    machine.succeed("mv /tmp/agenix-secrets/secret1.age.hidden /tmp/agenix-secrets/secret1.age")
    machine.succeed("cp /tmp/agenix-secrets/secret1.age '/tmp/agenix-secrets/space secret.age'")
    machine.succeed("printf '%s\\n' 'let old = import ./agenix-rules.nix; in old // { \"space secret.age\" = old.\"secret1.age\"; }' > /tmp/agenix-secrets/spaces.nix")
    machine.succeed("cd /tmp/agenix-secrets && HOME=/tmp/agenix-home AGENIX_RULES=./spaces.nix agenix -r -i /tmp/agenix-home/.ssh/id_ed25519")
    assert machine.succeed("cd /tmp/agenix-secrets && HOME=/tmp/agenix-home AGENIX_RULES=./spaces.nix agenix -d 'space secret.age' -i /tmp/agenix-home/.ssh/id_ed25519").strip() == "hello"

    status, output = machine.execute("cd /tmp/agenix-secrets && HOME=/tmp/agenix-home EDITOR=false timeout 20s script -q -e -c 'agenix -e secret2.age -i /tmp/agenix-home/.ssh/id_ed25519' /dev/null < /dev/null")
    assert status != 0 and status != 124 and "Editor failed" in output

    activation.start()
    activation.wait_for_unit("multi-user.target")
    generation = activation.succeed("readlink /run/agenix").strip()
    assert activation.succeed("cat /run/agenix-direct").strip() == "hello"
    activation.succeed("rm /etc/agenix-test/bad.age /etc/agenix-test/direct.age")
    activation.succeed("printf invalid > /etc/agenix-test/bad.age")
    activation.succeed("cp ${../example/-leading-hyphen-filename.age} /etc/agenix-test/direct.age")
    activation.fail("/run/current-system/activate > /tmp/activation.log 2>&1")
    assert activation.succeed("readlink /run/agenix").strip() == generation
    assert activation.succeed("cat /run/agenix/bad").strip() == "hello"
    assert activation.succeed("cat /run/agenix-direct").strip() == "hello"
    activation.succeed("cp ${../example/secret1.age} /etc/agenix-test/bad.age")
    activation.succeed("/run/current-system/activate > /tmp/activation.log 2>&1")
    assert activation.succeed("readlink /run/agenix").strip() != generation
    assert activation.succeed("cat /run/agenix-direct").strip() == "filename started with hyphen"
  '';
}
