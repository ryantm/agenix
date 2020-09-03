{
  description = "Secret management with age";
  outputs = { self, nixpkgs }: let
    systems = [
      "x86_64-linux"
      "i686-linux"
      "x86_64-darwin"
      "aarch64-linux"
      "armv6l-linux"
      "armv7l-linux"
    ];
    forAllSystems = f: nixpkgs.lib.genAttrs systems (system: f system);
  in {
    nixosModules.age = import ./modules/age.nix;
    # packages = forAllSystems (system: nixpkgs.legacyPackages.${system}.callPackage ./default.nix {});
#    defaultPackage = forAllSystems (system: self.packages.${system}.age-nix); # 
  };
}
