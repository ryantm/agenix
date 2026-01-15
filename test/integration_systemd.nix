# Test for age.installationMode = "systemd"
# This verifies that secrets are correctly decrypted by the systemd service
# and that dependent services can access them.
{
  nixpkgs ? <nixpkgs>,
  pkgs ? import <nixpkgs> {
    inherit system;
    config = { };
  },
  system ? builtins.currentSystem,
}:
pkgs.nixosTest {
  name = "agenix-systemd-mode";
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
        ./install_ssh_host_keys_simple.nix
      ];

      services.openssh.enable = true;

      # Use systemd mode for secret decryption
      age.installationMode = "systemd";

      age.secrets = {
        testsecret = {
          file = ../example/secret1.age;
          mode = "0400";
          owner = "root";
          group = "root";
        };
      };

      age.identityPaths = options.age.identityPaths.default;

      # Create a service that depends on agenix and reads the secret
      systemd.services.secret-consumer = {
        description = "Test service that consumes agenix secrets";
        after = [ "agenix-install-secrets.service" ];
        wants = [ "agenix-install-secrets.service" ];
        wantedBy = [ "multi-user.target" ];
        serviceConfig = {
          Type = "oneshot";
          RemainAfterExit = true;
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

  testScript = ''
    # Wait for the system to boot
    system1.wait_for_unit("multi-user.target")

    # Verify agenix-install-secrets.service succeeded
    system1.succeed("systemctl is-active agenix-install-secrets.service")

    # Verify the secret was decrypted
    system1.succeed("test -f /run/agenix/testsecret")

    # Verify the dependent service ran and consumed the secret
    system1.succeed("systemctl is-active secret-consumer.service")
    system1.succeed("test -f /tmp/secret-consumed")

    # Verify the secret content is correct
    secret_content = system1.succeed("cat /run/agenix/testsecret").strip()
    assert secret_content == "hello", f"Expected 'hello', got '{secret_content}'"

    # Verify consumed content matches
    consumed_content = system1.succeed("cat /tmp/secret-consumed").strip()
    assert consumed_content == "hello", f"Expected 'hello', got '{consumed_content}'"

    print("All systemd mode tests passed!")
  '';
}
