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

      age.secrets = {
        disabled.enable = false;
        direct-default = {
          file = ../example/secret1.age;
          symlink = false;
        };
        trimmed = {
          file = ../example/secret1.age;
          trimFinalNewline = true;
        };
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
            secrets.direct-default = {
              file = ../example/secret2.age;
              symlink = false;
            };
            secrets.trimmed = {
              file = ../example/secret2.age;
              trimFinalNewline = true;
            };
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
      system1.fail("test -e /run/user/1000/agenix/disabled")
      assert system1.succeed("cat /run/agenix/direct-default").strip() == "hello"
      assert system1.succeed("cat /run/user/1000/agenix/direct-default").strip() == "${secret2}"
      system1.fail("test -L /run/agenix/direct-default")
      system1.fail("test -L /run/user/1000/agenix/direct-default")
      assert system1.succeed("wc -c < /run/agenix/trimmed").strip() == "5"
      assert system1.succeed("wc -c < /run/user/1000/agenix/trimmed").strip() == "6"
      system1.send_chars("cat /run/user/$(id -u)/agenix/armored-secret > /tmp/3\n")
      system1.wait_for_file("/tmp/3")
      assert "${armored-secret}" in system1.succeed("cat /tmp/3")

      # Home Manager's quiet mode still reports a missing identity on stderr.
      home_log = system1.succeed("journalctl -b _SYSTEMD_USER_UNIT=agenix.service --no-pager -o cat")
      assert "[agenix] WARNING: config.age.identityPaths entry /home/user1/.ssh/this_key_wont_exist not present!" in home_log
      assert "[agenix] decrypting secrets..." not in home_log
      assert "decrypting '" not in home_log

      assert "${hyphen-secret}" in system1.succeed("cat /run/agenix/leading-hyphen")
      system1.fail("test -e /run/agenix/disabled")

    '';
}
