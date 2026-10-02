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
      test "$(cat "${config.age.derivedSecrets.rendered.path}")" = 'password=${secret}'
      test "$(/usr/bin/stat -L -f %Su:%Lp "${config.age.derivedSecrets.rendered.path}")" = runner:440
      generation="$(readlink "${config.age.secretsDir}")"
      ${config.launchd.daemons.activate-agenix.command}
      test "$(readlink "${config.age.secretsDir}")" = "$generation"
      rm "${config.age.secrets.system-secret.path}"
      ${config.launchd.daemons.activate-agenix.command}
      test "$(readlink "${config.age.secretsDir}")" != "$generation"
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
    secrets.system-secret.file = ../example/secret1.age;
    secrets.owned-secret = {
      file = ../example/secret1.age;
      owner = "runner";
    };
    derivedSecrets.rendered = {
      template = pkgs.writeText "darwin-template" "password=@system-secret@";
      secrets = [ config.age.secrets.system-secret ];
      owner = "runner";
      mode = "0440";
    };
  };

  # The owner must match a declared user, and nix-darwin users have no `group`.
  users.users.runner = { };

  environment.systemPackages = [ testScript ];

  system.stateVersion = 6;
}
