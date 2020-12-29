{
  description = "Secret management with age";

  inputs.flake-utils.url = "github:numtide/flake-utils";

  outputs = { self, nixpkgs, flake-utils }:
    let
      exports = {
        nixosModules.age = import ./modules/age.nix;
        overlay = import ./overlay.nix;
      };
      outputs = flake-utils.lib.eachDefaultSystem (system: {
        packages = nixpkgs.legacyPackages.${system}.callPackage ./default.nix { };
        defaultPackage = self.packages.${system}.agenix;
      });
    in
    exports // outputs;
}
