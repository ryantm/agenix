{ pkgs, home-manager }:
let
  inherit (pkgs) lib;
  rekey = pkgs.fetchFromGitHub {
    owner = "oddlama";
    repo = "agenix-rekey";
    rev = "8b9c179bc1300ab130c90f2d25426bf0e7a2b58d";
    hash = "sha256-GvINrdGznE7mGlDNjW0/PMgOJlC+Nl9MkfxALB4QvWs=";
  };
  root = "/agenix-generation-example";
  example = import ../example/generation.nix {
    inherit root;
    hostName = "fixture";
    hostPublicKey = lib.removeSuffix "\n" (builtins.readFile ../example_keys/system1.pub);
    masterIdentity = "${../example_keys/user1}";
    masterPublicKey = lib.removeSuffix "\n" (builtins.readFile ../example_keys/user1.pub);
  };
  rekeyModule = import (rekey + "/modules/agenix-rekey.nix") pkgs.path;
  nixos = import (pkgs.path + "/nixos/lib/eval-config.nix") {
    system = pkgs.stdenv.hostPlatform.system;
    modules = [
      ../modules/age.nix
      rekeyModule
      example
      {
        networking.hostName = "fixture";
        system.stateVersion = lib.trivial.release;
      }
    ];
  };
  home = home-manager.lib.homeManagerConfiguration {
    inherit pkgs;
    modules = [
      ../modules/age-home.nix
      rekeyModule
      example
      {
        home = {
          username = "fixture";
          homeDirectory = "/home/fixture";
          stateVersion = lib.trivial.release;
        };
      }
    ];
  };
  generate = import (rekey + "/apps/generate.nix") {
    inherit pkgs;
    userFlake.outPath = root;
    nodes = { inherit nixos home; };
    agePackage = p: p.rage;
  };
in
pkgs.runCommand "agenix-generation-example"
  {
    nativeBuildInputs = with pkgs; [
      rage
      openssh
      diffutils
    ];
  }
  ''
    mkdir project
    cd project
    touch flake.nix
    ${generate}/bin/agenix-generate
    sha256sum secrets/*.age secrets/*.pub > ../before
    ${generate}/bin/agenix-generate
    sha256sum -c ../before

    rage -d -i ${../example_keys/user1} secrets/api-token.age > ../token
    test "$(wc -c < ../token)" -eq 65
    base64 -d ../token > ../bytes
    test "$(wc -c < ../bytes)" -eq 48
    rage -d -i ${../example_keys/user1} secrets/deploy-key.age > ../key
    chmod 0600 ../key
    ssh-keygen -y -f ../key | cut -d ' ' -f 1,2 > ../key.pub
    cut -d ' ' -f 1,2 secrets/deploy-key.age.pub > ../expected.pub
    cmp ../key.pub ../expected.pub

    # The host is not a recipient of the master copy: rekeying is a separate
    # step before deployment. A repeat bootstrap must not rotate existing data.
    if rage -d -i ${../example_keys/system1} secrets/api-token.age > ../unexpected 2>/dev/null; then
      exit 1
    fi
    test ! -s ../unexpected
    touch "$out"
  ''
