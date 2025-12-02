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
    secrets.system-secret.file = ../example/secret1.age;
  };

  environment.systemPackages = [ testScript ];

  system.stateVersion = 6;
}
