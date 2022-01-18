args@{ pkgs ? <nixpkgs>, ... }:

with (import "${pkgs}/lib");

import "${pkgs}/nixos/tests/make-test-python.nix"
  (
    let
      sshdConf = {
        enable = true;
        hostKeys = [{ type = "ed25519"; path = "/etc/ssh/ssh_host_ed25519_key"; }];
      };
    in
    rec {
      name = "agenix-integration";

      nodes.system1 = { config, ... }: {
        imports = [
          ../modules/age.nix
          ./install_ssh_host_keys.nix
        ];

        services.openssh = sshdConf;

        age.secrets.passwordfile-user1.file = ../example/passwordfile-user1.age;

        users = {
          mutableUsers = false;

          users = {
            user1 = {
              isNormalUser = true;
              passwordFile = config.age.secrets.passwordfile-user1.path;
            };
          };
        };
      };

      nodes.system2 = {
        imports = [
          ../modules/age.nix
          ./install_ssh_host_keys.nix
        ];

        services.openssh = sshdConf;

        age.secrets.ex1 = {
          file = ../example/passwordfile-user1.age;
          action = "echo bar > /tmp/foo";
        };
      };

      nodes.system2After = recursiveUpdate nodes.system2 {
        age.secrets.ex1.file = ../example/secret1.age;
      };

      testScript =
        let
          user = "user1";
          password = "password1234";
        in
        { nodes, ... }:
        ''
          system1.start()
          system2.start()

          system1.wait_for_unit("multi-user.target")
          system1.wait_until_succeeds("pgrep -f 'agetty.*tty1'")
          system1.sleep(2)
          system1.send_key("alt-f2")
          system1.wait_until_succeeds("[ $(fgconsole) = 2 ]")
          system1.wait_for_unit("getty@tty2.service")
          system1.wait_until_succeeds("pgrep -f 'agetty.*tty2'")
          system1.wait_until_tty_matches(2, "login: ")
          system1.send_chars("${user}\n")
          system1.wait_until_tty_matches(2, "login: ${user}")
          system1.wait_until_succeeds("pgrep login")
          system1.sleep(2)
          system1.send_chars("${password}\n")
          system1.send_chars("whoami > /tmp/1\n")
          system1.wait_for_file("/tmp/1")
          assert "${user}" in system1.succeed("cat /tmp/1")

          system2.wait_for_unit("multi-user.target")
          system2.wait_until_fails("grep bar /tmp/foo")
          system2.wait_until_succeeds("${nodes.system2After.config.system.build.toplevel}/bin/switch-to-configuration test")
          system2.wait_until_succeeds("grep bar /tmp/foo")
        '';
    }
  )
  args
