args@{ nixpkgs ? <nixpkgs>, ... }:

with (import "${nixpkgs}/lib");

import "${nixpkgs}/nixos/tests/make-test-python.nix"
  (
    let
      sshdConf = {
        enable = true;
        hostKeys = [{ type = "ed25519"; path = "/etc/ssh/ssh_host_ed25519_key"; }];
      };

      testService = name: {
        systemd.services.${name} = {
          wantedBy = [ "multi-user.target" ];
          reload = "touch /tmp/${name}-reloaded";
          # restarting a serivice stops it
          preStop = "touch /tmp/${name}-stopped";
          serviceConfig = {
            Type = "oneshot";
            RemainAfterExit = true;
          };
        };
      };

      testSecret = name: {
        imports = map testService [ "${name}-reloadUnit" "${name}-restartUnit" ];
        age.secrets.${name} = {
          file = ../example/secret1.age;
          onChange = "touch /tmp/${name}-onChange-executed";
          reloadUnits = [ "${name}-reloadUnit.service" ];
          restartUnits = [ "${name}-restartUnit.service" ];
        };
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
        ]
        ++ map testSecret [
          "noChange"
          "fileChange"
          "secretChange"
          "secretChangeWeirdPath"
          "pathChange"
          "pathChangeNoSymlink"
          "modeChange"
          "symlinkOn"
          "symlinkOff"
        ]
        # add these services so they get started before the secret is added
        ++ (testSecret "secretAdded").imports;


        age.secrets.secretChangeWeirdPath.path = "/tmp/secretChangeWeirdPath";
        age.secrets.pathChangeNoSymlink.symlink = false;
        age.secrets.symlinkOn.symlink = false;

        services.openssh = sshdConf;
      };

      nodes.system2After = { lib, ... }: {
        imports = [
          nodes.system2
          # services have already been added
          (builtins.removeAttrs (testSecret "secretAdded") [ "imports" ])
        ];
        age.secrets.fileChange.file = lib.mkForce ../example/secret1-copy.age;
        age.secrets.secretChange.file = lib.mkForce ../example/passwordfile-user1.age;
        age.secrets.secretChangeWeirdPath.file = lib.mkForce ../example/passwordfile-user1.age;
        age.secrets.pathChange.path = lib.mkForce "/tmp/pathChange";
        age.secrets.pathChangeNoSymlink.path = lib.mkForce "/tmp/pathChangeNoSymlink";
        age.secrets.modeChange.mode = lib.mkForce "0777";
        age.secrets.symlinkOn.symlink = lib.mkForce true;
        age.secrets.symlinkOff.symlink = lib.mkForce false;
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
          # for these secrets the content doesn't change at all
          system2_noChange_secrets = [
            "noChange",
            "fileChange",
            "symlinkOn",
            "symlinkOff",
          ]
          system2_change_secrets = [
            "secretChange",
            "secretChangeWeirdPath",
            "pathChange",
            "pathChangeNoSymlink",
            "modeChange",
            "secretAdded",
          ]
          system2_secrets = system2_noChange_secrets + system2_change_secrets
          system2.wait_for_unit("multi-user.target")
          for secret in system2_secrets:
            system2.wait_for_unit(secret + "-reloadUnit")
            system2.wait_for_unit(secret + "-restartUnit")

          def test_not_changed(secret):
            system2.fail("test -f /tmp/" + secret + "-reloadUnit-reloaded")
            system2.fail("test -f /tmp/" + secret + "-reloadUnit-restarted")
            system2.fail("test -f /tmp/" + secret + "-restartUnit-reloaded")
            system2.fail("test -f /tmp/" + secret + "-restartUnit-restarted")
            system2.fail("test -f /tmp/" + secret + "-onChange-executed")
          def test_changed(secret):
            system2.wait_for_file("/tmp/" + secret + "-onChange-executed")
            system2.wait_for_file("/tmp/" + secret + "-reloadUnit-reloaded")
            system2.wait_for_file("/tmp/" + secret + "-restartUnit-stopped")
            system2.fail("test -f /tmp/" + secret + "-reloadUnit-restarted")
            system2.fail("test -f /tmp/" + secret + "-restartUnit-reloaded")

          # nothing should happen at startup
          for secret in system2_secrets:
            test_not_changed(secret)

          # apply changes
          system2.succeed(
              "${nodes.system2After.config.system.build.toplevel}/bin/switch-to-configuration test"
          )
          for secret in system2_noChange_secrets:
            test_not_changed(secret)
          for secret in system2_change_secrets:
            test_changed(secret)
        '';
    }
  )
  args
