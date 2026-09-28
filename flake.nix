{
  description = "Secret management with age";

  inputs = {
    nixpkgs.url = "github:NixOS/nixpkgs/nixos-26.05";
  };

  outputs =
    {
      self,
      nixpkgs,
    }:
    let
      # nixpkgs cannot bootstrap GHC on these systems. Omit nixfmt-tree and
      # agenix's shellcheck install check there.
      noGhcSystems = [
        "armv6l-linux"
        "armv7l-linux"
        "powerpc64le-linux"
        "riscv64-linux"
        "x86_64-freebsd"
      ];
      # age also needs a Go bootstrap that nixpkgs cannot provide on FreeBSD.
      packageSystems = nixpkgs.lib.filter (
        system: system != "x86_64-freebsd"
      ) nixpkgs.lib.systems.flakeExposed;
      eachSystem = nixpkgs.lib.genAttrs packageSystems;
      formatterSystems = nixpkgs.lib.filter (
        system: !(builtins.elem system noGhcSystems)
      ) nixpkgs.lib.systems.flakeExposed;
    in
    {
      nixosModules.age = ./modules/age.nix;
      nixosModules.default = self.nixosModules.age;

      darwinModules.age = ./modules/age.nix;
      darwinModules.default = self.darwinModules.age;

      homeManagerModules.age = ./modules/age-home.nix;
      homeManagerModules.default = self.homeManagerModules.age;

      overlays.default = import ./overlay.nix;

      formatter = nixpkgs.lib.genAttrs formatterSystems (
        system: nixpkgs.legacyPackages.${system}.nixfmt-tree
      );

      packages = eachSystem (system: {
        agenix = nixpkgs.legacyPackages.${system}.callPackage ./pkgs/agenix.nix {
          runShellcheck = !(builtins.elem system noGhcSystems);
        };
        doc = nixpkgs.legacyPackages.${system}.callPackage ./pkgs/doc.nix { inherit self; };
        default = self.packages.${system}.agenix;
      });

      checks.x86_64-linux.cli = self.packages.x86_64-linux.agenix;
    };
}
