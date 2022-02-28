{
  description = "Secret management with age";

  outputs = { self, nixpkgs }:
  let
    agenix = system: nixpkgs.legacyPackages.${system}.callPackage ./pkgs/agenix.nix {};
  in {

    nixosModules.age = import ./modules/age.nix;
    nixosModule = self.nixosModules.age;

    overlay = import ./overlay.nix;

    packages."aarch64-linux".agenix = agenix "aarch64-linux";
    defaultPackage."aarch64-linux" = self.packages."aarch64-linux".agenix;

    packages."i686-linux".agenix = agenix "i686-linux";
    defaultPackage."i686-linux" = self.packages."i686-linux".agenix;

    packages."x86_64-darwin".agenix = agenix "x86_64-darwin";
    defaultPackage."x86_64-darwin" = self.packages."x86_64-darwin".agenix;

    packages."x86_64-linux".agenix = agenix "x86_64-linux";
    defaultPackage."x86_64-linux" = self.packages."x86_64-linux".agenix;
    checks."x86_64-linux".integration = import ./test/integration.nix {
      inherit nixpkgs; pkgs = nixpkgs.legacyPackages."x86_64-linux"; system = "x86_64-linux";
    };

  };

}
