{
  config,
  pkgs,
  options,
  ...
}:
let
  secret = "hello";
  testScript = pkgs.writeShellApplication {
    name = "agenix-integration";
    text = ''
      grep "${secret}" "${config.age.secrets.system-secret.path}"
    '';
  };
in
{
  imports = [
    ./install_ssh_host_keys_darwin.nix
    ../modules/age.nix
  ];

  age = {
    identityPaths = options.age.identityPaths.default ++ [ "/etc/ssh/this_key_wont_exist" ];
    pluginPackages = [
      (pkgs.writeShellScriptBin "agenix-test-plugin" ''
        printf 'plugin ran\n' | grep -q 'plugin ran'
      '')
    ];
    ageBin = "${pkgs.writeShellScript "age-with-test-plugin" ''
      set -e
      agenix-test-plugin
      exec ${pkgs.age}/bin/age "$@"
    ''}";
    secrets.system-secret.file = ../example/secret1.age;
    secrets.owned-secret = {
      file = ../example/secret1.age;
      owner = "runner";
    };
  };

  # The owner must match a declared user, and nix-darwin users have no `group`.
  users.users.runner = { };

  environment.systemPackages = [ testScript ];

  system.stateVersion = 6;
}
