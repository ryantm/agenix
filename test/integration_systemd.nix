# Test for age.installationMode = "systemd"
# This verifies that secrets are correctly decrypted by the systemd service
# and that dependent services can access them.
{ pkgs }:
pkgs.testers.nixosTest {
  name = "agenix-systemd-mode";
  nodes.system1 =
    {
      config,
      pkgs,
      ...
    }:
    {
      imports = [
        ../modules/age.nix
      ];

      systemd.sysusers.enable = true;
      users.users.secret-reader = {
        isSystemUser = true;
        group = "users";
      };

      # Use systemd mode for secret decryption
      age.installationMode = "systemd";

      age.secrets = {
        testsecret = {
          file = ../example/secret1.age;
          mode = "0400";
          owner = "secret-reader";
          group = "users";
        };
        disabled.enable = false;
      };

      age.identityPaths = [ "/var/lib/agenix-test/identity" ];
      systemd.services.agenix-install-secrets = {
        requires = [ "provide-identity.service" ];
        after = [ "provide-identity.service" ];
      };
      systemd.services.provide-identity = {
        serviceConfig.Type = "oneshot";
        script = ''
          install -Dm0600 ${../example_keys/system1} /var/lib/agenix-test/identity
        '';
      };

      # Create a service that depends on agenix and reads the secret
      systemd.services.secret-consumer = {
        description = "Test service that consumes agenix secrets";
        after = [ "agenix-install-secrets.service" ];
        requires = [ "agenix-install-secrets.service" ];
        wantedBy = [ "multi-user.target" ];
        serviceConfig = {
          Type = "oneshot";
          RemainAfterExit = true;
          User = "secret-reader";
          ExecStart = pkgs.writeShellScript "consume-secret" ''
            set -euo pipefail
            if [ -r "${config.age.secrets.testsecret.path}" ]; then
              cat "${config.age.secrets.testsecret.path}" > /tmp/secret-consumed
              echo "Secret consumed successfully"
            else
              echo "ERROR: Secret not readable"
              exit 1
            fi
          '';
        };
      };
    };

  nodes.barrier = { ... }: {
    imports = [ ../modules/age.nix ];
    systemd.sysusers.enable = false;
    services.userborn.enable = false;
    age.identityPaths = [ "${../example_keys/system1}" ];
    age.secrets.secret.file = ../example/secret1.age;
    age.secrets.disabled.enable = false;
  };

  testScript = ''
    # Wait for the system to boot
    system1.wait_for_unit("multi-user.target")

    # Verify agenix-install-secrets.service succeeded
    system1.succeed("systemctl is-active agenix-install-secrets.service")

    # Verify the secret was decrypted
    system1.succeed("test -f /run/agenix/testsecret")
    assert system1.succeed("stat -Lc %U /run/agenix/testsecret").strip() == "secret-reader"
    system1.fail("test -e /run/agenix/disabled")

    # Verify the dependent service ran and consumed the secret
    system1.succeed("systemctl is-active secret-consumer.service")
    system1.succeed("test -f /tmp/secret-consumed")

    # Verify the secret content is correct
    secret_content = system1.succeed("cat /run/agenix/testsecret").strip()
    assert secret_content == "hello", f"Expected 'hello', got '{secret_content}'"

    # Verify consumed content matches
    consumed_content = system1.succeed("cat /tmp/secret-consumed").strip()
    assert consumed_content == "hello", f"Expected 'hello', got '{consumed_content}'"

    # The activation-mode service verifies every enabled secret and reports
    # missing files. It never decrypts them itself.
    barrier.wait_for_unit("multi-user.target")
    barrier.succeed("systemctl is-active agenix-install-secrets.service")
    barrier.succeed("rm /run/agenix/secret")
    barrier.fail("systemctl restart agenix-install-secrets.service")
    barrier.fail("test -f /run/agenix/secret")
    barrier.succeed("/run/current-system/activate")
    barrier.succeed("systemctl restart agenix-install-secrets.service")
    assert barrier.succeed("cat /run/agenix/secret").strip() == "hello"
  '';
}
