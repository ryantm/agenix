{
  pkgs,
  config,
  options,
  lib,
  ...
}: {
  imports = [../modules/age-home.nix];

  age = {
    identityPaths = options.age.identityPaths.default ++ ["/Users/user1/.ssh/this_key_wont_exist"];
    secrets.user-secret.file = ../example/secret2.age;
  };

  home = rec {
    username = "runner";
    homeDirectory = lib.mkForce "/Users/${username}";
    stateVersion = lib.trivial.release;
  };

  home.file = let
    name = "agenix-home-integration";
  in {
    ${name}.source = pkgs.writeShellApplication {
      inherit name;
      text = let
        secret = "world!";
      in ''
        diff -q "${config.age.secrets.user-secret.path}" <(printf '${secret}\n')
      '';
    };
  };
}
