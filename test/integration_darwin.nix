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
      test "$(wc -c < "${config.age.secrets.trimmed.path}" | tr -d '[:space:]')" = 5
    '';
  };
in
{
  imports = [
    ./install_ssh_host_keys_darwin.nix
    ../modules/age.nix
  ];

  age = {
    identityStrategy = "ordered";
    identityPaths = options.age.identityPaths.default ++ [ "/etc/ssh/this_key_wont_exist" ];
    secrets.system-secret.file = ../example/secret1.age;
    secrets.trimmed = {
      file = ../example/secret1.age;
      trimFinalNewline = true;
    };
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
