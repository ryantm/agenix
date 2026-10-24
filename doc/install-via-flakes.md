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

## Using the NixOS and Home Manager modules together

The modules both define `age` options, in separate configuration scopes.
Importing both into the NixOS `modules` list causes an "already declared"
option error. Put the Home Manager module inside Home Manager instead.
For example, within your flake outputs where `nixpkgs`, `agenix`, and
`home-manager` are in scope:

```nix
nixosConfigurations.yourhostname = nixpkgs.lib.nixosSystem {
  system = "x86_64-linux";
  modules = [
    ./configuration.nix
    agenix.nixosModules.default
    home-manager.nixosModules.home-manager
    {
      home-manager.sharedModules = [ agenix.homeManagerModules.default ];
      home-manager.users.alice = {
        home.stateVersion = "26.05";
        age.secrets.user-secret.file = ./secrets/user-secret.age;
      };
    }
  ];
};
```

Here `alice` is a user declared by your NixOS configuration. System secrets
belong under `age.secrets` in that configuration; Alice's secrets belong
under `home-manager.users.alice.age.secrets`. Each scope has its own
`age.identityPaths` and plaintext destinations.

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
