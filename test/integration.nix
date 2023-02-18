{
  nixpkgs ? <nixpkgs>,
  pkgs ?
    import <nixpkgs> {
      inherit system;
      config = {};
    },
  system ? builtins.currentSystem,
}:
pkgs.nixosTest {
  name = "agenix-integration";
  nodes.system1 = {
    config,
    pkgs,
    options,
    ...
  }: {
    imports = [
      ../modules/age.nix
      ./install_ssh_host_keys.nix
    ];

    services.openssh.enable = true;

    age.secrets.passwordfile-user1 = {
      file = ../example/passwordfile-user1.age;
    };

    age.identityPaths = options.age.identityPaths.default ++ ["/etc/ssh/this_key_wont_exist"];

    environment.systemPackages = [
      (pkgs.callPackage ../pkgs/agenix.nix {})
    ];

    users = {
      mutableUsers = false;

      users = {
        user1 = {
          isNormalUser = true;
          passwordFile = config.age.secrets.passwordfile-user1.path;
          uid = 1000;
        };
      };
    };
  };

  testScript = let
    user = "user1";
    password = "password1234";
  in ''
    system1.wait_for_unit("multi-user.target")
    system1.wait_until_succeeds("pgrep -f 'agetty.*tty1'")
    system1.sleep(2)
    system1.send_key("alt-f2")
    system1.wait_until_succeeds("[ $(fgconsole) = 2 ]")
    system1.wait_for_unit("getty@tty2.service")
    system1.wait_until_succeeds("pgrep -f 'agetty.*tty2'")
    system1.wait_until_tty_matches("2", "login: ")
    system1.send_chars("${user}\n")
    system1.wait_until_tty_matches("2", "login: ${user}")
    system1.wait_until_succeeds("pgrep login")
    system1.sleep(2)
    system1.send_chars("${password}\n")
    system1.send_chars("whoami > /tmp/1\n")
    system1.wait_for_file("/tmp/1")
    assert "${user}" in system1.succeed("cat /tmp/1")

    system1.succeed('cp -a "${../example}/." /tmp/secrets')
    system1.succeed('chmod u+w /tmp/secrets/*.age')

    before_hash = system1.succeed('sha256sum /tmp/secrets/passwordfile-user1.age').split()
    print(system1.succeed('cd /tmp/secrets; agenix -r -i /home/user1/.ssh/id_ed25519'))
    after_hash = system1.succeed('sha256sum /tmp/secrets/passwordfile-user1.age').split()

    # Ensure we actually have hashes
    for h in [before_hash, after_hash]:
        assert len(h) == 2, "hash should be [hash, filename]"
        assert h[1] == "/tmp/secrets/passwordfile-user1.age", "filename is incorrect"
        assert len(h[0].strip()) == 64, "hash length is incorrect"
    assert before_hash[0] != after_hash[0], "hash did not change with rekeying"

    # user1 can edit passwordfile-user1.age
    system1.wait_for_file("/tmp/")
    system1.send_chars("cd /tmp/secrets; EDITOR=cat agenix -e passwordfile-user1.age\n")
    system1.send_chars("echo $? >/tmp/exit_code\n")
    system1.wait_for_file("/tmp/exit_code")
    assert "0" in system1.succeed("cat /tmp/exit_code")
    system1.send_chars("rm /tmp/exit_code\n")

    # user1 can edit even if bogus id_rsa present
    system1.send_chars("echo bogus > ~/.ssh/id_rsa\n")
    system1.send_chars("cd /tmp/secrets; EDITOR=cat agenix -e passwordfile-user1.age -i /home/user1/.ssh/id_ed25519\n")
    system1.send_chars("echo $? >/tmp/exit_code\n")
    system1.wait_for_file("/tmp/exit_code")
    assert "0" in system1.succeed("cat /tmp/exit_code")
    system1.send_chars("rm /tmp/exit_code\n")
  '';
}
