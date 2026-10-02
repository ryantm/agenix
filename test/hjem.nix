{ pkgs, hjem }:
let
  configure = import ../lib/hjem-configuration.nix;
  homeDirectory = "/home/alice";
  configuration =
    file: identityPaths:
    configure {
      inherit pkgs homeDirectory;
      modules = [
        {
          age = {
            inherit identityPaths;
            secrets.example = {
              inherit file;
              trimFinalNewline = true;
            };
            secrets.custom = {
              inherit file;
              path = "${homeDirectory}/.config/example/secret";
            };
            secrets.disabled = {
              enable = false;
            };
          };
        }
      ];
    };
  first = configuration ../example/secret1.age [ "${homeDirectory}/.ssh/id_ed25519" ];
  second = configuration ../example/secret2.age [ "${homeDirectory}/.ssh/replacement" ];
  missing = configuration ../example/secret2.age [ "${homeDirectory}/.ssh/missing" ];
  empty = configure { inherit pkgs homeDirectory; };
  configFile =
    name: value:
    pkgs.writeText name ''
      builtins.fromJSON ${pkgs.lib.generators.toPretty { } (builtins.toJSON value)}
    '';
in
assert empty.manifest.files == [ ] && empty.packages == [ ];
assert first.paths.example == "${homeDirectory}/.local/state/agenix/example";
pkgs.testers.nixosTest {
  name = "agenix-hjem-standalone";
  nodes.machine = {
    # No system agenix, Hjem, or Home Manager module is imported.
    users.users.alice = {
      isNormalUser = true;
      uid = 1000;
      linger = true;
    };
    nix.settings.experimental-features = [
      "nix-command"
      "flakes"
    ];
    environment.systemPackages = [ (pkgs.callPackage (hjem + "/cli/package.nix") { }) ];
    environment.etc = {
      "hjem-first.nix".source = configFile "hjem-first.nix" first;
      "hjem-second.nix".source = configFile "hjem-second.nix" second;
      "hjem-missing.nix".source = configFile "hjem-missing.nix" missing;
      "hjem-public-test-identity".source = ../example_keys/user1;
    };
  };
  testScript = ''
    machine.wait_for_unit("multi-user.target")
    machine.wait_for_unit("user@1000.service")

    def alice(command):
        import shlex
        return "runuser -u alice -- env HOME=${homeDirectory} USER=alice XDG_RUNTIME_DIR=/run/user/1000 bash -c " + shlex.quote(command)

    def switch(config):
        machine.succeed(alice("hjem standalone switch --config /etc/hjem-" + config + ".nix"))

    activate = "${homeDirectory}/.local/state/hjem/standalone/current-profile/bin/agenix-hjem-activate"
    secret = "${first.paths.example}"
    custom = "${first.paths.custom}"

    machine.succeed("install -d -m700 -o alice -g users ${homeDirectory}/.ssh")
    machine.succeed("install -m600 -o alice -g users /etc/hjem-public-test-identity ${homeDirectory}/.ssh/id_ed25519")

    with subtest("Standalone switch installs the user service and decrypt command"):
        switch("first")
        machine.succeed(alice(activate))
        assert machine.succeed(alice("cat " + secret)) == "hello"
        assert machine.succeed(alice("cat " + custom)) == "hello\n"
        machine.succeed("test $(stat -Lc %U:%a " + secret + ") = alice:400")
        machine.succeed("test ! -e ${homeDirectory}/.local/state/agenix/disabled")
        machine.succeed(alice("test $(readlink ${homeDirectory}/.local/state/agenix) = /run/user/1000/agenix.d/1"))

    with subtest("A changed identity and ciphertext are applied without stale service state"):
        machine.succeed(alice("mv ~/.ssh/id_ed25519 ~/.ssh/replacement"))
        switch("second")
        machine.succeed(alice(activate))
        assert machine.succeed(alice("cat " + secret)) == "world!"
        machine.succeed("test ! -e /run/user/1000/agenix.d/1")

    with subtest("Missing identities fail visibly and preserve the previous generation"):
        switch("missing")
        machine.fail(alice(activate))
        assert machine.succeed(alice("cat " + secret)) == "world!"
        machine.succeed("test ! -e /run/user/1000/agenix.d/3")

    with subtest("Hjem rollback restores the previous service and package"):
        machine.succeed(alice("hjem standalone rollback"))
        machine.succeed(alice(activate))
        assert machine.succeed(alice("cat " + secret)) == "world!"

    with subtest("The next login decrypts secrets using the enabled user service"):
        machine.succeed("systemctl stop user@1000.service user-runtime-dir@1000.service")
        machine.succeed("test ! -e /run/user/1000/agenix.d")
        machine.succeed("systemctl start user@1000.service")
        machine.wait_until_succeeds(alice("test -f " + secret))
        assert machine.succeed(alice("cat " + secret)) == "world!"
  '';
}
