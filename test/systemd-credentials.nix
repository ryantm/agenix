{ pkgs }:
let
  inherit (pkgs) lib;
  fixtures =
    pkgs.runCommand "agenix-public-credential-fixtures" { nativeBuildInputs = [ pkgs.age ]; }
      ''
        mkdir "$out"
        printf 'binary\000\377\nline\n' > "$out/binary"
        age -R ${../example_keys/user1.pub} -o "$out/binary.age" "$out/binary"
      '';
  makeNode = tpm: { config, ... }: {
    imports = [ ../modules/age-systemd-credentials.nix ];
    virtualisation.tpm.enable = tpm;
    age.identityPaths = [ "/var/lib/agenix-credential-test/identity" ];
    age.systemdCredentials = {
      token = {
        file = "/var/lib/agenix-credential-test/token.age";
        withKey = if tpm then "host+tpm2" else "host";
        services = [ "credential-reader" ];
      };
      disabled.enable = false;
      binary = {
        file = "${fixtures}/binary.age";
        withKey = if tpm then "host+tpm2" else "host";
        services = [ "credential-reader" ];
      };
    };
    systemd.services.agenix-encrypt-credentials = {
      requires = [ "credential-inputs.service" ];
      after = [ "credential-inputs.service" ];
      # Allow the regression to exercise several failures without waiting.
      unitConfig.StartLimitIntervalSec = 0;
    };
    systemd.services.credential-inputs = {
      serviceConfig = {
        Type = "oneshot";
        RemainAfterExit = true;
      };
      script = ''
        install -Dm600 ${../example_keys/user1} /var/lib/agenix-credential-test/identity
        if ! test -e /var/lib/agenix-credential-test/token.age; then
          install -m600 ${../example/secret1.age} /var/lib/agenix-credential-test/token.age
        fi
      '';
    };
    systemd.services.credential-reader = {
      wantedBy = [ "multi-user.target" ];
      path = [ pkgs.diffutils ];
      serviceConfig = {
        Type = "oneshot";
        RemainAfterExit = true;
        DynamicUser = true;
        StateDirectory = "agenix-credential-reader";
        PrivateMounts = true;
      };
      script = ''
        # The application reads systemd's decrypted credential, not the blob.
        test ! -r ${config.age.systemdCredentials.token.path}
        cmp "$CREDENTIALS_DIRECTORY/binary" ${fixtures}/binary
        cat "$CREDENTIALS_DIRECTORY/token" > "$STATE_DIRECTORY/result"
      '';
    };
    virtualisation.additionalPaths = [ ../example/secret2.age ];
  };
in
pkgs.testers.nixosTest {
  name = "agenix-systemd-credentials";
  nodes.host = makeNode false;
  nodes.tpm = makeNode true;
  testScript = ''
    import shlex

    for machine in [host, tpm]:
        machine.wait_for_unit("multi-user.target")
        machine.succeed("systemctl is-active agenix-encrypt-credentials.service")
        machine.succeed("systemctl is-active credential-reader.service")
        assert machine.succeed("cat /var/lib/agenix-credential-reader/result") == "hello\n"
        machine.succeed("test ! -e /run/agenix; test ! -e /run/agenix-credentials/current/disabled")
        machine.succeed("test $(stat -Lc %u:%g:%a /run/agenix-credentials/current/token) = 0:0:400")
        machine.fail("grep -r -F hello /run/agenix-credentials")
        assert machine.succeed("systemd-creds decrypt --name=token /run/agenix-credentials/current/token -") == "hello\n"
        machine.fail("systemd-creds decrypt --name=wrong /run/agenix-credentials/current/token -")
        old = machine.succeed("readlink /run/agenix-credentials/current").strip()

        with subtest("Failed input leaves the previous encrypted generation intact"):
            machine.succeed("printf invalid > /var/lib/agenix-credential-test/token.age")
            machine.fail("systemctl restart agenix-encrypt-credentials.service")
            assert machine.succeed("readlink /run/agenix-credentials/current").strip() == old
            assert machine.succeed("find /run/agenix-credentials -maxdepth 1 -type d | wc -l").strip() == "2"
            machine.succeed("mv /var/lib/agenix-credential-test/identity /var/lib/agenix-credential-test/identity.saved")
            machine.fail("systemctl restart agenix-encrypt-credentials.service")
            assert machine.succeed("readlink /run/agenix-credentials/current").strip() == old
            machine.succeed("mv /var/lib/agenix-credential-test/identity.saved /var/lib/agenix-credential-test/identity")

        with subtest("Consumers receive a newly decrypted credential when restarted"):
            machine.succeed("install -m600 ${../example/secret2.age} /var/lib/agenix-credential-test/token.age")
            machine.succeed("systemctl restart agenix-encrypt-credentials.service")
            machine.succeed("test ! -d /run/agenix-credentials/" + old)
            # A consumer stopped by the failed required unit can be started
            # again after preparation recovers.
            machine.succeed("systemctl restart credential-reader.service")
            assert machine.succeed("cat /var/lib/agenix-credential-reader/result") == "world!\n"
            machine.fail("grep -r -F 'world!' /run/agenix-credentials")

        if machine is host:
            foreign_blob = machine.succeed("cat /run/agenix-credentials/current/token")
        else:
            machine.succeed("printf %s " + shlex.quote(foreign_blob) + " > /root/foreign.cred")
            machine.fail("systemd-creds decrypt --name=token /root/foreign.cred -")

        machine.shutdown()
  '';
}
