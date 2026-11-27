{
  nixpkgs ? <nixpkgs>,
  pkgs ? import <nixpkgs> {
    inherit system;
    config = { };
  },
  system ? builtins.currentSystem,
  home-manager ? <home-manager>,
}:
pkgs.testers.nixosTest {
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
      services.openssh.settings.PasswordAuthentication = true;
      environment.systemPackages = [
        pkgs.sshpass
        pkgs.util-linux
      ];

      age.secrets = {
        disabled.enable = false;
        passwordfile-user1.file = ../example/passwordfile-user1.age;
        leading-hyphen.file = ../example/-leading-hyphen-filename.age;
        named-owner = {
          file = ../example/secret1.age;
          owner = "getpsyched";
        };
      };

      age.identityPaths = options.age.identityPaths.default ++ [ "/etc/ssh/this_key_wont_exist" ];

      users = {
        mutableUsers = false;

        users = {
          user1 = {
            isNormalUser = true;
            hashedPasswordFile = config.age.secrets.passwordfile-user1.path;
            uid = 1000;
          };
          primary = {
            name = "getpsyched";
            isNormalUser = true;
            group = "users";
            uid = 1001;
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
            verbosity = "quiet";
            secrets.disabled.enable = false;
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

  nodes.disabled = { pkgs, ... }: {
    imports = [
      ../modules/age.nix
      "${home-manager}/nixos"
    ];
    age.secrets.only-disabled.enable = false;
    home-manager.users.user1 = { ... }: {
      imports = [ ../modules/age-home.nix ];
      home.username = "user1";
      home.homeDirectory = "/home/user1";
      home.stateVersion = pkgs.lib.trivial.release;
      age.secrets.only-disabled.enable = false;
    };
    users.users.user1 = {
      isNormalUser = true;
      uid = 1000;
    };
  };

  nodes.forcedDisabled = { pkgs, ... }: {
    imports = [
      ../modules/age.nix
      "${home-manager}/nixos"
    ];
    age.enable = false;
    age.secrets.configured.file = ../example/secret1.age;
    users.users.user1 = {
      isNormalUser = true;
      uid = 1000;
    };
    home-manager.users.user1 = { ... }: {
      imports = [ ../modules/age-home.nix ];
      home.username = "user1";
      home.homeDirectory = "/home/user1";
      home.stateVersion = pkgs.lib.trivial.release;
      age.enable = false;
      age.secrets.configured.file = ../example/secret2.age;
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
      system1.succeed("test -e /home/user1/.config/systemd/user/agenix.service")
      disabled.wait_for_unit("multi-user.target")
      disabled.fail("test -e /run/agenix")
      disabled.fail("systemctl cat agenix-install-secrets.service")
      disabled.fail("systemctl cat agenix-chown.service")
      disabled.fail("test -e /home/user1/.config/systemd/user/agenix.service")
      forcedDisabled.wait_for_unit("multi-user.target")
      forcedDisabled.fail("test -e /run/agenix")
      forcedDisabled.fail("test -e /home/user1/.config/systemd/user/agenix.service")
      # The owner is a Linux username, while its users.users attribute is "primary".
      # The default secret group should come from that user's configuration.
      owner_group = system1.succeed("stat -Lc '%U:%G' /run/agenix/named-owner").strip()
      assert owner_group == "getpsyched:users", owner_group
      # Exercise the installed password hash through PAM without racing virtual
      # keyboard input. Keep the user manager alive after the SSH session ends.
      system1.wait_for_unit("sshd.service")
      system1.succeed("loginctl enable-linger ${user}")
      login = "ssh -o StrictHostKeyChecking=no -o UserKnownHostsFile=/dev/null -o PreferredAuthentications=password -o PubkeyAuthentication=no -o NumberOfPasswordPrompts=1 ${user}@localhost whoami"
      system1.fail("sshpass -p incorrect-test-password " + login)
      assert system1.succeed("sshpass -p ${password} " + login).strip() == "${user}"
      system1.wait_for_file("/run/user/1000/agenix/secret2")
      assert "${secret2}" in system1.succeed("runuser -u ${user} -- cat /run/user/1000/agenix/secret2")
      system1.fail("test -e /run/user/1000/agenix/disabled")
      assert "${armored-secret}" in system1.succeed("runuser -u ${user} -- cat /run/user/1000/agenix/armored-secret")

      # Home Manager's quiet mode still reports a missing identity on stderr.
      home_log = system1.succeed("journalctl -b _SYSTEMD_USER_UNIT=agenix.service --no-pager -o cat")
      assert "[agenix] WARNING: config.age.identityPaths entry /home/user1/.ssh/this_key_wont_exist not present!" in home_log
      assert "[agenix] decrypting secrets..." not in home_log
      assert "decrypting '" not in home_log

      assert "${hyphen-secret}" in system1.succeed("cat /run/agenix/leading-hyphen")
      system1.fail("test -e /run/agenix/disabled")

    '';
}
