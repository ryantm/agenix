{ pkgs }:
let
  inherit (pkgs) lib;
  # This passphrase and the keys it protects are public fixtures only.
  passphrase = "agenix-public-test-passphrase";
  fixtures =
    pkgs.runCommand "agenix-public-encrypted-identities"
      {
        nativeBuildInputs = [
          pkgs.age
          pkgs.openssh
        ];
      }
      ''
        mkdir "$out"
        cp ${../example_keys/user1} "$out/ssh-key"
        chmod 0600 "$out/ssh-key"
        ssh-keygen -q -p -P "" -N ${passphrase} -f "$out/ssh-key"
        age-keygen -o native-key
        age -r "$(age-keygen -y native-key)" -o "$out/native-secret.age" ${pkgs.writeText "fixture" "hello\n"}
        age -d -i ${../example_keys/user1} ${../example/passwordfile-user1.age} | \
          age -r "$(age-keygen -y native-key)" -o "$out/native-password.age"
        AGE_PASSPHRASE=${passphrase} age -e -j batchpass -o "$out/native-key.age" native-key
      '';
  agent = pkgs.writeText "agenix-test-password-agent.py" ''
    import configparser
    import glob
    import os
    import socket
    import time

    answered = set()
    while True:
        for path in glob.glob("/run/systemd/ask-password/ask.*"):
            try:
                config = configparser.ConfigParser(interpolation=None)
                config.read(path)
                request = config["Ask"]
                if request.get("Id") != "agenix-identity-unlock":
                    continue
                destination = request["Socket"]
                if destination in answered:
                    continue
                mode = "correct"
                if os.path.exists("/run/agenix-test-answer"):
                    with open("/run/agenix-test-answer") as f:
                        mode = f.read().strip()
                if mode == "hold":
                    continue
                answer = b"-" if mode == "cancel" else b"+" + (
                    b"wrong" if mode == "wrong" else b"${passphrase}"
                )
                with socket.socket(socket.AF_UNIX, socket.SOCK_DGRAM) as sock:
                    sock.sendto(answer, destination)
                answered.add(destination)
                with open("/run/agenix-test-answers", "a") as f:
                    f.write(mode + "\n")
            except (KeyError, OSError):
                pass
        time.sleep(0.02)
  '';
  makeNode = format: early: { config, ... }: {
    imports = [ ../modules/age-identity-unlock.nix ];
    services.userborn.enable = early;
    age.identityUnlock = {
      enable = true;
      inherit format;
      file = "${fixtures}/" + (if format == "ssh" then "ssh-key" else "native-key.age");
      timeout = 5;
    };
    age.installationMode = if early then "activation" else "systemd";
    age.secrets.secret.file =
      if format == "ssh" then ../example/secret1.age else "${fixtures}/native-secret.age";
    users.users.reader = lib.mkIf early {
      isNormalUser = true;
      uid = 1000;
      hashedPasswordFile = config.age.secrets.password.path;
    };
    age.secrets.password = lib.mkIf early { file = "${fixtures}/native-password.age"; };
    systemd.services.agenix-unlock-identity = {
      requires = [ "test-password-agent.service" ];
      after = [ "test-password-agent.service" ];
      unitConfig.StartLimitIntervalSec = 0;
    };
    systemd.services.agenix-install-secrets.unitConfig.StartLimitIntervalSec = 0;
    systemd.services.test-rebuild-pipe.serviceConfig = {
      Type = "oneshot";
      RemainAfterExit = true;
      ExecStart = "${config.systemd.package}/bin/systemd-run --pipe --no-ask-password --wait --collect --quiet ${config.systemd.package}/bin/systemctl --no-ask-password restart agenix-unlock-identity.service";
    };
    systemd.services.test-password-agent = {
      unitConfig.DefaultDependencies = false;
      before = [ "agenix-unlock-identity.service" ];
      serviceConfig = {
        Type = "simple";
        ExecStart = "${pkgs.python3}/bin/python3 ${agent}";
      };
    };
  };
in
pkgs.testers.nixosTest {
  name = "agenix-identity-unlock";
  nodes.ssh = makeNode "ssh" false;
  nodes.native = makeNode "age" false;
  nodes.early = makeNode "age" true;
  testScript = ''
    for machine in [ssh, native, early]:
        machine.wait_for_unit("multi-user.target")
        machine.succeed("systemctl is-active agenix-unlock-identity.service")
        machine.succeed("systemctl is-active agenix-install-secrets.service")
        assert machine.succeed("cat /run/agenix/secret") == "hello\n"
        machine.succeed("test $(stat -c %u:%g:%a /run/agenix-unlocked-identity/key) = 0:0:400")
        assert machine.succeed("findmnt -n -o FSTYPE /run/agenix-unlocked-identity").strip() == "ramfs"
        assert machine.succeed("wc -l < /run/agenix-test-answers").strip() == "1"
        if machine is early:
            machine.succeed('test "$(getent shadow reader | cut -d: -f2)" = "$(cat /run/agenix/password)"')

        with subtest("A rebuild-style pipe does not require a terminal for the passphrase"):
            machine.succeed("printf hold > /run/agenix-test-answer")
            machine.succeed("systemctl --no-ask-password start --no-block test-rebuild-pipe.service")
            machine.wait_until_succeeds("test -n \"$(find /run/systemd/ask-password -name 'ask.*' -print)\"")
            machine.fail("test -e /run/agenix-unlocked-identity/key")
            process_data = machine.succeed("ps axeww")
            assert "${passphrase}" not in process_data
            machine.succeed("printf correct > /run/agenix-test-answer")
            machine.wait_until_succeeds("systemctl is-active agenix-unlock-identity.service")
            machine.wait_for_unit("test-rebuild-pipe.service")
            machine.succeed("systemctl restart agenix-install-secrets.service")
            assert machine.succeed("cat /run/agenix/secret") == "hello\n"

        for answer in ["wrong", "cancel", "hold"]:
            machine.succeed("printf " + answer + " > /run/agenix-test-answer")
            # The fixture agent answers; systemctl must not also start an agent
            # that could consume the test driver's command channel as input.
            machine.fail("systemctl --no-ask-password restart agenix-unlock-identity.service")
            machine.fail("test -e /run/agenix-unlocked-identity/key")
            machine.fail("mountpoint -q /run/agenix-unlocked-identity")
            machine.succeed("printf correct > /run/agenix-test-answer")
            machine.succeed("systemctl --no-ask-password restart agenix-unlock-identity.service")
            machine.succeed("systemctl restart agenix-install-secrets.service")

        unlock_log = machine.succeed("journalctl -b -u agenix-unlock-identity.service --no-pager -o cat")
        assert "${passphrase}" not in unlock_log
        machine.succeed("systemctl stop agenix-unlock-identity.service")
        machine.fail("test -e /run/agenix-unlocked-identity/key")
        machine.fail("mountpoint -q /run/agenix-unlocked-identity")
        machine.shutdown()
  '';
}
