{
  nixpkgs ? <nixpkgs>,
  pkgs ? import <nixpkgs> {
    inherit system;
    config = { };
  },
  system ? builtins.currentSystem,
  home-manager ? <home-manager>,
}:
pkgs.nixosTest {
  name = "agenix-integration";
  nodes.system1 =
    {
      config,
      pkgs,
      options,
      ...
    }:
    {
      imports = [
        ../modules/age.nix
        ./install_ssh_host_keys.nix
        "${home-manager}/nixos"
      ];

      services.openssh.enable = true;

      age.secrets = {
        passwordfile-user1.file = ../example/passwordfile-user1.age;
        leading-hyphen.file = ../example/-leading-hyphen-filename.age;
      };

      age.identityPaths = options.age.identityPaths.default ++ [ "/etc/ssh/this_key_wont_exist" ];

      environment.systemPackages = [
        (pkgs.callPackage ../pkgs/agenix.nix { })
      ];

      users = {
        mutableUsers = false;

        users = {
          user1 = {
            isNormalUser = true;
            hashedPasswordFile = config.age.secrets.passwordfile-user1.path;
            uid = 1000;
          };
        };
      };

      home-manager.users.user1 =
        { options, ... }:
        {
          imports = [
            ../modules/age-home.nix
          ];

          home.stateVersion = pkgs.lib.trivial.release;

          age = {
            identityPaths = options.age.identityPaths.default ++ [ "/home/user1/.ssh/this_key_wont_exist" ];
            secrets.secret2 = {
              # Only decryptable by user1's key
              file = ../example/secret2.age;
            };
            secrets.secret2Path = {
              file = ../example/secret2.age;
              path = "/home/user1/secret2";
            };
            secrets.armored-secret = {
              file = ../example/armored-secret.age;
            };
          };
        };
    };

  testScript =
    let
      user = "user1";
      password = "password1234";
      secret2 = "world!";
      hyphen-secret = "filename started with hyphen";
      armored-secret = "Hello World!";
    in
    ''
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
      system1.send_chars("cat /run/user/$(id -u)/agenix/secret2 > /tmp/2\n")
      system1.wait_for_file("/tmp/2")
      assert "${secret2}" in system1.succeed("cat /tmp/2")
      system1.send_chars("cat /run/user/$(id -u)/agenix/armored-secret > /tmp/3\n")
      system1.wait_for_file("/tmp/3")
      assert "${armored-secret}" in system1.succeed("cat /tmp/3")

      assert "${hyphen-secret}" in system1.succeed("cat /run/agenix/leading-hyphen")

      userDo = lambda input : f"sudo -u user1 -- bash -c 'set -eou pipefail; cd /tmp/secrets; {input}'"

      before_hash = system1.succeed(userDo('sha256sum passwordfile-user1.age')).split()
      print(system1.succeed(userDo('agenix -r -i /home/user1/.ssh/id_ed25519')))
      after_hash = system1.succeed(userDo('sha256sum passwordfile-user1.age')).split()

      # Ensure we actually have hashes
      for h in [before_hash, after_hash]:
          assert len(h) == 2, "hash should be [hash, filename]"
          assert h[1] == "passwordfile-user1.age", "filename is incorrect"
          assert len(h[0].strip()) == 64, "hash length is incorrect"
      assert before_hash[0] != after_hash[0], "hash did not change with rekeying"

      # user1 can edit passwordfile-user1.age
      system1.succeed(userDo("EDITOR=cat agenix -e passwordfile-user1.age"))

      # user1 can edit even if bogus id_rsa present
      system1.succeed(userDo("echo bogus > ~/.ssh/id_rsa"))
      system1.fail(userDo("EDITOR=cat agenix -e passwordfile-user1.age"))
      system1.succeed(userDo("EDITOR=cat agenix -e passwordfile-user1.age -i /home/user1/.ssh/id_ed25519"))
      system1.succeed(userDo("rm ~/.ssh/id_rsa"))

      # user1 can edit a secret by piping in contents
      system1.succeed(userDo("echo 'secret1234' | agenix -e passwordfile-user1.age"))

      # user1 can recreate the secret without decrypting it
      system1.succeed(userDo("echo 'secret5678' | agenix -c passwordfile-user1.age"))
      assert "secret5678" in system1.succeed(userDo("agenix -d passwordfile-user1.age"))

      # finally, the plain text should not linger around anywhere in the filesystem.
      system1.fail("grep -r secret1234 /tmp")
    '';
}
