{
  description = "agenix integration tests";

  inputs = {
    nixpkgs.url = "github:NixOS/nixpkgs/nixos-26.05";
    darwin = {
      url = "github:nix-darwin/nix-darwin/nix-darwin-26.05";
      inputs.nixpkgs.follows = "nixpkgs";
    };
    home-manager = {
      url = "github:nix-community/home-manager/release-26.05";
      inputs.nixpkgs.follows = "nixpkgs";
    };
  };

  outputs =
    {
      self,
      nixpkgs,
      darwin,
      home-manager,
    }:
    let
      testDir = self.outPath;
    in
    {
      checks =
        nixpkgs.lib.genAttrs [ "aarch64-darwin" "x86_64-darwin" ] (system: {
          missing-identities = import (testDir + "/missing-identities.nix") {
            pkgs = nixpkgs.legacyPackages.${system};
          };
          ciphertext-validation = import (testDir + "/ciphertext-validation.nix") {
            pkgs = nixpkgs.legacyPackages.${system};
          };
          trim-newline = import (testDir + "/trim-newline.nix") {
            pkgs = nixpkgs.legacyPackages.${system};
          };
          shared-installer = import (testDir + "/shared-installer.nix") {
            pkgs = nixpkgs.legacyPackages.${system};
          };
          integration =
            (darwin.lib.darwinSystem {
              inherit system;
              modules = [
                (testDir + "/integration_darwin.nix")

                # Allow new-style nix commands in CI
                { nix.extraOptions = "experimental-features = nix-command flakes"; }

                home-manager.darwinModules.home-manager
                {
                  home-manager = {
                    verbose = true;
                    useGlobalPkgs = true;
                    useUserPackages = true;
                    backupFileExtension = "hmbak";
                    users.runner = testDir + "/integration_hm_darwin.nix";
                  };
                }
              ];
            }).system;
        })
        // {
          x86_64-linux.home-service = import (testDir + "/home-service.nix") {
            inherit home-manager;
            pkgs = nixpkgs.legacyPackages.x86_64-linux;
          };
          x86_64-linux.missing-identities = import (testDir + "/missing-identities.nix") {
            pkgs = nixpkgs.legacyPackages.x86_64-linux;
          };
          x86_64-linux.ciphertext-validation = import (testDir + "/ciphertext-validation.nix") {
            pkgs = nixpkgs.legacyPackages.x86_64-linux;
          };
          x86_64-linux.trim-newline = import (testDir + "/trim-newline.nix") {
            pkgs = nixpkgs.legacyPackages.x86_64-linux;
          };
          x86_64-linux.integration = import (testDir + "/integration.nix") {
            inherit nixpkgs home-manager;
            pkgs = nixpkgs.legacyPackages.x86_64-linux;
            system = "x86_64-linux";
          };
          x86_64-linux.userborn = import (testDir + "/userborn.nix") {
            pkgs = nixpkgs.legacyPackages.x86_64-linux;
          };
          x86_64-linux.verbosity = import (testDir + "/verbosity.nix") {
            pkgs = nixpkgs.legacyPackages.x86_64-linux;
          };
          x86_64-linux.shared-installer = import (testDir + "/shared-installer.nix") {
            pkgs = nixpkgs.legacyPackages.x86_64-linux;
          };
        };

      darwinConfigurations.integration-x86_64.system = self.checks.x86_64-darwin.integration;
      darwinConfigurations.integration-aarch64.system = self.checks.aarch64-darwin.integration;

      # Work-around for https://github.com/nix-community/home-manager/issues/3075
      legacyPackages = nixpkgs.lib.genAttrs [ "aarch64-darwin" "x86_64-darwin" ] (system: {
        homeConfigurations.integration-darwin = home-manager.lib.homeManagerConfiguration {
          pkgs = nixpkgs.legacyPackages.${system};
          modules = [ (testDir + "/integration_hm_darwin.nix") ];
        };
      });
    };
}
