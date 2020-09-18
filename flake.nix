{
  description = "Secret management with age";

  inputs.flake-utils.url = "github:numtide/flake-utils";

  outputs = { self, nixpkgs, flake-utils }:
    flake-utils.lib.eachDefaultSystem (system:
      {
        nixosModules.age = import ./modules/age.nix;
        packages = nixpkgs.legacyPackages.${system}.callPackage ./default.nix {};
        defaultPackage = self.packages.${system}.agenix;
      });
}
