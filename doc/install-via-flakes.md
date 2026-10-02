# Install via Flakes {#install-via-flakes}

## Install module via Flakes

```nix
{
  inputs.nixpkgs.url = "github:NixOS/nixpkgs/nixos-26.05";
  inputs.agenix.url = "github:ryantm/agenix";
  # optional, not necessary for the module
  #inputs.agenix.inputs.nixpkgs.follows = "nixpkgs";

  outputs = { self, nixpkgs, agenix }: {
    # change `yourhostname` to your actual hostname
    nixosConfigurations.yourhostname = nixpkgs.lib.nixosSystem {
      # change to your system:
      system = "x86_64-linux";
      modules = [
        ./configuration.nix
        agenix.nixosModules.default
      ];
    };
  };
}
```

## Install Home Manager module via Flakes

```nix
{
  inputs.nixpkgs.url = "github:NixOS/nixpkgs/nixos-26.05";
  inputs.agenix.url = "github:ryantm/agenix";
  inputs.home-manager.url = "github:nix-community/home-manager/release-26.05";
  inputs.home-manager.inputs.nixpkgs.follows = "nixpkgs";

  outputs = { self, nixpkgs, agenix, home-manager, ... }: {
    homeConfigurations.username = home-manager.lib.homeManagerConfiguration {
      # Change the system to match your machine.
      pkgs = nixpkgs.legacyPackages.x86_64-linux;
      modules = [
        agenix.homeManagerModules.default
        {
          home.username = "username";
          home.homeDirectory = "/home/username";
          home.stateVersion = "26.05";
        }
      ];
    };
  };
}
```

## Install CLI via Flakes

You don't need to install it,

```ShellSession
nix run github:ryantm/agenix -- --help
```

but, if you want to (change the system based on your system):

```nix
{
  environment.systemPackages = [ agenix.packages.x86_64-linux.default ];
}
```
