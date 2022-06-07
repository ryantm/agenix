args@{ nixpkgs ? <nixpkgs>, ... }:

with (import "${nixpkgs}/lib");

import "${nixpkgs}/nixos/tests/make-test-python.nix"
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

      nodes.system2 = { pkgs, ... }: {
        imports = [
          ../modules/age.nix
          ./install_ssh_host_keys.nix
        ];

        services.openssh = sshdConf;

        age.secrets.ex1 = {
          file = ../example/passwordfile-user1.age;
          onChange = "touch /tmp/onChange-executed";
          reloadUnits = [ "reloadTest.service" ];
          restartUnits = [ "restartTest.service" ];
        };

        systemd.services.reloadTest = {
          wantedBy = [ "multi-user.target" ];
          path = [ pkgs.coreutils ];
          reload = "touch /tmp/reloadTest-reloaded";
          preStop = "touch /tmp/reloadTest-stopped";
          serviceConfig = {
            Type = "oneshot";
            RemainAfterExit = true;
          };
        };

        systemd.services.restartTest = {
          wantedBy = [ "multi-user.target" ];
          path = [ pkgs.coreutils ];
          reload = "touch /tmp/restartTest-reloaded";
          preStop = "touch /tmp/restartTest-stopped";
          serviceConfig = {
            Type = "oneshot";
            RemainAfterExit = true;
          };
        };
      };

      nodes.system2After = { lib, ... }: {
        imports = [ nodes.system2 ];
        age.secrets.ex1.file = lib.mkForce ../example/secret1.age;
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

          # test changing secret
          system2.wait_for_unit("multi-user.target")
          system2.wait_for_unit("reloadTest.service")
          system2.wait_for_unit("restartTest.service")
          # none of the files should exist yet. start blank
          system2.fail("test -f /tmp/onChange-executed")
          system2.fail("test -f /tmp/reloadTest-reloaded")
          system2.fail("test -f /tmp/restartTest-stopped")
          system2.fail("test -f /tmp/reloadTest-stopped")
          # change the secret
          system2.succeed(
              "${nodes.system2After.config.system.build.toplevel}/bin/switch-to-configuration test"
          )

          system2.wait_for_file("/tmp/onChange-executed")
          system2.wait_for_file("/tmp/reloadTest-reloaded")
          system2.wait_for_file("/tmp/restartTest-stopped")
          system2.fail("test -f /tmp/reloadTest-stopped")
          system2.fail("test -f /tmp/restartTest-reloaded")
        '';
    }
  )
  args
