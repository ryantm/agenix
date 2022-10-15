{
  description = "Secret management with age";

  inputs = {
    nixpkgs.url = "github:nixos/nixpkgs/nixos-21.11";
    flake-parts.url = "github:hercules-ci/flake-parts";
  };

  outputs = {
    self,
    flake-parts,
    nixpkgs,
  }:
    flake-parts.lib.mkFlake {inherit self;} {
      systems = [
        "aarch64-linux"
        "i686-linux"
        "x86_64-linux"
        "x86_64-darwin"
        "aarch64-darwin"
      ];
      perSystem = ctx @ {
        system,
        pkgs,
        ...
      }: {
        packages.default = ctx.config.packages.agenix;
        packages.agenix = pkgs.callPackage ./pkgs/agenix.nix {};
        checks.integration = import ./test/integration.nix {
          inherit system pkgs nixpkgs;
        };
      };
      flake.nixosModules = {
        default = self.nixosModules.age;
        age = import ./modules/age.nix;
      };
      flake.overlays.default = final: prev: {
        agenix = prev.callPackage ./pkgs/agenix.nix {};
      };
    };
}
