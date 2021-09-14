{
nixpkgs ? <nixpkgs>,
pkgs ? import <nixpkgs> { inherit system; config = {}; },
system ? builtins.currentSystem
} @args:

import "${nixpkgs}/nixos/tests/make-test-python.nix" ({ pkgs, ...}: {
  name = "agenix-integration";

  nodes.system1 = { config, lib, ... }: {

    imports = [
      ../modules/age.nix
      ./install_ssh_host_keys.nix
    ];

    services.openssh.enable = true;

    age.secrets.passwordfile-user1 = {
      file = ../example/passwordfile-user1.age;
    };

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

  testScript =
  let
    user = "user1";
    password = "password1234";
  in ''
    system1.wait_for_unit("multi-user.target")

    with subtest("Decrypting age-encrypted ${user} password works"):
        system1.succeed("test -e /run/secrets/passwordfile-user1")

    with subtest("Logging in with ${user} works"):
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

    with subtest("Decrypted password not moved on dry-activation"):
        system1.succeed("rm /run/secrets/passwordfile-user1")
        out = system1.succeed("/run/current-system/bin/switch-to-configuration dry-activate")
        assert "[agenix] dry-run, not moving decrypted secret" in out
        system1.succeed('test -z "$(ls -A /run/secrets)"')
  '';
}) args
