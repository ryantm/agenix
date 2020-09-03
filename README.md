# agenix

[age](https://github.com/FiloSottile/age)-encrypted secrets for NixOS.

# Features

* Secrets are encrypted with SSH keys
** system public keys via `ssh-keyscan`
** can use public keys available on GitHub for users (for example, https://github.com/ryantm.keys)
* No GPG
* Very little code, so it should be easy for you to audit

# Installation

Choose one of the following methods:

#### [niv](https://github.com/nmattia/niv) (Current recommendation)

First add it to niv:

```console
$ niv add ryantm/agenix
```

  Than add the following to your configuration.nix in the `imports` list:

```nix
{
  imports = [ "${(import ./nix/sources.nix).agenix}/modules/age" ];
}
```

#### nix-channel

  As root run:

```console
$ nix-channel --add https://github.com/ryantm/agenix/archive/master.tar.gz agenix
$ nix-channel --update
```

  Than add the following to your configuration.nix in the `imports` list:

```nix
{
  imports = [ <agenix/modules/age> ];
}
```

#### fetchTarball

  Add the following to your configuration.nix:

``` nix
{
  imports = [ "${builtins.fetchTarball "https://github.com/ryantm/agenix/archive/master.tar.gz"}/modules/age" ];
}
```

  or with pinning:

```nix
{
  imports = let
    # replace this with an actual commit id or tag
    commit = "298b235f664f925b433614dc33380f0662adfc3f";
  in [
    "${builtins.fetchTarball {
      url = "https://github.com/ryantm/agenix/archive/${commit}.tar.gz";
      # replace this with an actual hash
      sha256 = "0000000000000000000000000000000000000000000000000000";
    }}/modules/age"
  ];
}
```

#### Flakes

``` nix
{
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
        agenix.nixosModules.age
      ];
    };
  };
}
```

# Tutorial

# Threat model
