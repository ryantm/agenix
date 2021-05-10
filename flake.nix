{
  description = "Awesome secret management with age";

  inputs.flake-utils.url = "github:numtide/flake-utils";

  outputs = { self, nixpkgs, flake-utils }:
    let
      exports = {
        nixosModules.age = import ./modules/age.nix;
        overlay = import ./overlay.nix;
      };

      outputs = flake-utils.lib.eachDefaultSystem (system:
        let pkgs = nixpkgs.legacyPackages.${system}; in
        {
          defaultPackage = pkgs.callPackage ./default.nix { };
          packages = self.defaultPackage;
        }
        // pkgs.lib.optionalAttrs pkgs.stdenv.isLinux {
          checks.integration = import ./test/integration.nix {
            inherit nixpkgs system pkgs;
          };
        }
      );
    in
    exports // outputs;
}
