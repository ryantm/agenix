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
  };

  outputs = {
    self,
    nixpkgs,
    darwin,
    home-manager,
  }: let
    agenix = system: nixpkgs.legacyPackages.${system}.callPackage ./pkgs/agenix.nix {};
    doc = system: nixpkgs.legacyPackages.${system}.callPackage ./pkgs/doc.nix {};
  in {
    nixosModules.age = import ./modules/age.nix;
    nixosModules.default = self.nixosModules.age;

    darwinModules.age = import ./modules/age.nix;
    darwinModules.default = self.darwinModules.age;

    homeManagerModules.age = import ./modules/age-home.nix;
    homeManagerModules.default = self.homeManagerModules.age;

    overlays.default = import ./overlay.nix;

    formatter.x86_64-darwin = nixpkgs.legacyPackages.x86_64-darwin.alejandra;
    packages.x86_64-darwin.agenix = agenix "x86_64-darwin";
    packages.x86_64-darwin.doc = doc "x86_64-darwin";
    packages.x86_64-darwin.default = self.packages.x86_64-darwin.agenix;

    formatter.aarch64-darwin = nixpkgs.legacyPackages.aarch64-darwin.alejandra;
    packages.aarch64-darwin.agenix = agenix "aarch64-darwin";
    packages.aarch64-darwin.doc = doc "aarch64-darwin";
    packages.aarch64-darwin.default = self.packages.aarch64-darwin.agenix;

    formatter.aarch64-linux = nixpkgs.legacyPackages.aarch64-linux.alejandra;
    packages.aarch64-linux.agenix = agenix "aarch64-linux";
    packages.aarch64-linux.doc = doc "aarch64-linux";
    packages.aarch64-linux.default = self.packages.aarch64-linux.agenix;

    formatter.i686-linux = nixpkgs.legacyPackages.i686-linux.alejandra;
    packages.i686-linux.agenix = agenix "i686-linux";
    packages.i686-linux.doc = doc "i686-linux";
    packages.i686-linux.default = self.packages.i686-linux.agenix;

    formatter.x86_64-linux = nixpkgs.legacyPackages.x86_64-linux.alejandra;
    packages.x86_64-linux.agenix = agenix "x86_64-linux";
    packages.x86_64-linux.default = self.packages.x86_64-linux.agenix;
    packages.x86_64-linux.doc = doc "x86_64-linux";
    checks.x86_64-linux.integration = import ./test/integration.nix {
      inherit nixpkgs;
      pkgs = nixpkgs.legacyPackages.x86_64-linux;
      system = "x86_64-linux";
    };
    checks."aarch64-darwin".integration =
      (darwin.lib.darwinSystem {
        system = "aarch64-darwin";
        modules = [./test/integration_darwin.nix "${darwin.outPath}/pkgs/darwin-installer/installer.nix"];
      })
      .system;
    checks."x86_64-darwin".integration =
      (darwin.lib.darwinSystem {
        system = "x86_64-darwin";
        modules = [./test/integration_darwin.nix "${darwin.outPath}/pkgs/darwin-installer/installer.nix"];
      })
      .system;

    darwinConfigurations.integration.system = self.checks."x86_64-darwin".integration;
  };
}
