{ pkgs, home-manager }:
let
  # These credentials and keys are public test fixtures, not real accounts.
  fixtures = pkgs.runCommand "agenix-home-service-fixtures" { nativeBuildInputs = [ pkgs.age ]; } ''
    mkdir "$out"
    age-keygen -o "$out/native-key"
    for version in first second; do
      cat > "$version.yml" <<EOF
    github.example.com:
      user: alice
      oauth_token: agenix-public-test-$version
      git_protocol: https
      users:
        alice:
          oauth_token: agenix-public-test-$version
    EOF
    done
    age -R ${../example_keys/user1.pub} -o "$out/first.age" first.yml
    age -r "$(age-keygen -y "$out/native-key")" -o "$out/second.age" second.yml
  '';
  home =
    version:
    home-manager.lib.homeManagerConfiguration {
      inherit pkgs;
      modules = [
        ../modules/age-home.nix
        ({ config, ... }: {
          home = {
            username = "alice";
            homeDirectory = "/home/alice";
            stateVersion = "26.05";
          };
          programs.gh.enable = true;
          age.identityPaths = [
            "/home/alice/.ssh/id_ed25519"
          ]
          ++ pkgs.lib.optional (version == "second") "/home/alice/.config/age/key.txt";
          age.secrets.gh-hosts = {
            file = "${fixtures}/${version}.age";
            path = "${config.xdg.configHome}/gh/hosts.yml";
          };
        })
      ];
    };
  first = home "first";
  second = home "second";
in
pkgs.testers.nixosTest {
  name = "agenix-home-service";
  nodes.machine = {
    # Exercise standalone Home Manager, without either NixOS integration module.
    users.users.alice = {
      isNormalUser = true;
      uid = 1000;
      linger = true;
    };
    environment.etc = {
      "agenix-home-first".source = first.activationPackage;
      "agenix-home-second".source = second.activationPackage;
      "agenix-test-ssh-key".source = ../example_keys/user1;
      "agenix-test-native-key".source = "${fixtures}/native-key";
    };
  };
  testScript = ''
    import shlex

    machine.wait_for_unit("multi-user.target")
    machine.wait_for_unit("user@1000.service")

    def alice(command):
        return "runuser -u alice -- env HOME=/home/alice USER=alice XDG_RUNTIME_DIR=/run/user/1000 bash -c " + shlex.quote(command)

    token = "${pkgs.gh}/bin/gh auth token --hostname github.example.com"
    machine.succeed(alice("mkdir -p -m700 ~/.ssh ~/.config/age"))
    machine.succeed("install -m600 -o alice -g users /etc/agenix-test-ssh-key /home/alice/.ssh/id_ed25519")

    with subtest("Home Manager starts agenix and installs the application's secret path"):
        machine.succeed(alice("/etc/agenix-home-first/activate"))
        machine.wait_until_succeeds(alice("test -f /home/alice/.config/gh/hosts.yml"))
        assert machine.succeed(alice(token)).strip() == "agenix-public-test-first"
        machine.succeed("test -L /home/alice/.config/gh/hosts.yml")
        machine.succeed("test $(stat -Lc %U:%a /home/alice/.config/gh/hosts.yml) = alice:400")
        old_exec = machine.succeed(alice("systemctl --user show agenix.service -p ExecStart --value"))

    with subtest("A switch reloads the service and uses a newly configured native identity"):
        machine.succeed(alice("unlink /home/alice/.ssh/id_ed25519"))
        machine.succeed("install -m600 -o alice -g users /etc/agenix-test-native-key /home/alice/.config/age/key.txt")
        machine.succeed(alice("/etc/agenix-home-second/activate"))
        machine.wait_until_succeeds(alice("test \"$(" + token + ")\" = agenix-public-test-second"))
        new_exec = machine.succeed(alice("systemctl --user show agenix.service -p ExecStart --value"))
        assert old_exec != new_exec
        # No test command performs daemon-reload or restarts agenix manually.
        machine.succeed("test ! -e /run/user/1000/agenix.d/1")
        machine.succeed("test $(stat -Lc %U:%a /home/alice/.config/gh/hosts.yml) = alice:400")
  '';
}
