{
  description = "Secret management with age";

  inputs = {
    nixpkgs.url = "github:NixOS/nixpkgs/nixos-unstable";
    darwin = {
      url = "github:lnl7/nix-darwin/master";
      inputs.nixpkgs.follows = "nixpkgs";
    };
    home-manager = {
      url = "github:nix-community/home-manager";
      inputs.nixpkgs.follows = "nixpkgs";
    };
    systems.url = "github:nix-systems/default";
  };

  outputs = {
    self,
    nixpkgs,
    darwin,
    home-manager,
    systems,
  }: let
    eachSystem = nixpkgs.lib.genAttrs (import systems);
  in {
    nixosModules.age = import ./modules/age.nix;
    nixosModules.default = self.nixosModules.age;

    darwinModules.age = import ./modules/age.nix;
    darwinModules.default = self.darwinModules.age;

    homeManagerModules.age = import ./modules/age-home.nix;
    homeManagerModules.default = self.homeManagerModules.age;

    overlays.default = import ./overlay.nix;

    formatter = eachSystem (system: nixpkgs.legacyPackages.${system}.alejandra);

    packages = eachSystem (system: {
      agenix = nixpkgs.legacyPackages.${system}.callPackage ./pkgs/agenix.nix {};
      doc = nixpkgs.legacyPackages.${system}.callPackage ./pkgs/doc.nix {inherit self;};
      default = self.packages.${system}.agenix;
    });

    checks =
      nixpkgs.lib.genAttrs ["aarch64-darwin" "x86_64-darwin"] (system: {
        integration =
          (darwin.lib.darwinSystem {
            inherit system;
            modules = [
              ./test/integration_darwin.nix
              home-manager.darwinModules.home-manager
              {
                home-manager = {
                  verbose = true;
                  useGlobalPkgs = true;
                  useUserPackages = true;
                  backupFileExtension = "hmbak";
                  users.runner = ./test/integration_hm_darwin.nix;
                };
              }
            ];
          })
          .system;
      })
      // {
        x86_64-linux.integration = import ./test/integration.nix {
          inherit nixpkgs home-manager;
          pkgs = nixpkgs.legacyPackages.x86_64-linux;
          system = "x86_64-linux";
        };
      };

    darwinConfigurations.integration-x86_64.system = self.checks.x86_64-darwin.integration;
    darwinConfigurations.integration-aarch64.system = self.checks.aarch64-darwin.integration;

    # Work-around for https://github.com/nix-community/home-manager/issues/3075
    legacyPackages = nixpkgs.lib.genAttrs ["aarch64-darwin" "x86_64-darwin"] (system: {
      homeConfigurations.integration-darwin = home-manager.lib.homeManagerConfiguration {
        pkgs = nixpkgs.legacyPackages.${system};
        modules = [./test/integration_hm_darwin.nix];
      };
    });
  };
}
