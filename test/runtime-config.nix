{ pkgs }:
let
  # Only public dummy values are present in this fixture.
  ciphertext = pkgs.runCommand "agenix-fah-config.age" { nativeBuildInputs = [ pkgs.age ]; } ''
    cat <<'EOF' | age -R ${../example_keys/system1.pub} -o "$out"
    <config>
      <passkey v="0123456789abcdef0123456789abcdef"/>
      <account-token v="agenix-public-test-token"/>
      <machine-name v="agenix credential fixture"/>
    </config>
    EOF
  '';
in
pkgs.testers.nixosTest {
  name = "agenix-runtime-config";
  nodes.machine =
    {
      config,
      lib,
      pkgs,
      ...
    }:
    {
      imports = [ ../modules/age.nix ];
      # This private identity is a public repository fixture.
      age.identityPaths = [ "${../example_keys/system1}" ];
      age.secrets.fah-config.file = ciphertext;
      services.foldingathome = {
        enable = true;
        user = "agenix-test";
        team = 1;
        package = pkgs.writeShellScriptBin "fah-client" ''
          exec ${lib.getExe pkgs.fahclient} --config "$CREDENTIALS_DIRECTORY/config.xml" "$@"
        '';
        # Parse and print configuration, then exit without networking or work units.
        extraArgs = [ "--print" ];
      };
      systemd.services.foldingathome.serviceConfig = {
        LoadCredential = [ "config.xml:${config.age.secrets.fah-config.path}" ];
        Type = "oneshot";
        RemainAfterExit = true;
        StandardOutput = "file:/run/fah-config-report.txt";
      };
    };
  testScript = ''
    machine.wait_for_unit("multi-user.target")
    machine.wait_for_unit("foldingathome.service")
    report = machine.succeed("cat /run/fah-config-report.txt")
    assert 'agenix credential fixture' in report, report
    assert 'agenix-test' in report, report
    assert '0123456789abcdef0123456789abcdef' in report, report
    assert 'agenix-public-test-token' in report, report
    machine.succeed("test $(stat -Lc %U:%a /run/agenix/fah-config) = root:400")
    machine.succeed("test $(systemctl show foldingathome.service -p DynamicUser --value) = yes")
    # The service script contains only a credential file path and public flags.
    unit = machine.succeed("systemctl cat foldingathome.service")
    assert '0123456789abcdef0123456789abcdef' not in unit
    assert 'agenix-public-test-token' not in unit
  '';
}
