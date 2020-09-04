# agenix

[age](https://github.com/FiloSottile/age)-encrypted secrets for NixOS.

It consists of a NixOS module `age`, and a CLI tool called `agenix`
used for editing and rekeying the secret files.

## Features

* Secrets are encrypted with SSH keys
  * system public keys via `ssh-keyscan`
  * can use public keys available on GitHub for users (for example, https://github.com/ryantm.keys)
* No GPG
* Very little code, so it should be easy for you to audit
* Encrypted secrets are stored in the Nix store, so a separate distribution mechanism is not necessary

## Installation

Choose one of the following methods:

### [niv](https://github.com/nmattia/niv) (Current recommendation)

First add it to niv:

```console
$ niv add ryantm/agenix
```

#### Module

Then add the following to your configuration.nix in the `imports` list:

```nix
{
  imports = [ "${(import ./nix/sources.nix).agenix}/modules/age" ];
}
```

### nix-channel

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

### fetchTarball

  Add the following to your configuration.nix:

```nix
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

### Flakes

#### Module

```nix
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

#### CLI

You don't need to install it:

```console
nix run github:ryantm/agenix -- --help
```

if you want to (change the system based on your system):

```nix
{
  environment.systemPackages = [ agenix.defaultPackage.x86_64-linux ];
}
```



## Tutorial

1. Make a directory to store secrets and `secrets.nix` file for listing secrets and their public keys:

   ```console
   $ mkdir secrets
   $ cd secerts
   $ touch secrets.nix
   ```
2. Add public keys to `secrets.nix` file (hint: use `ssh-keyscan` or GitHub (for example, https://github.com/ryantm.keys)):
   ```nix
   let
     user1 = "ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAIL0idNvgGiucWgup/mP78zyC23uFjYq0evcWdjGQUaBH";
     system1 = "ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAIPJDyIr/FSz1cJdcoW69R+NrWzwGK/+3gJpqD1t8L2zE";
   in
   {
     "secret1.age".publicKeys = [ user1 system1 ];
     "secret2.age".publicKeys = [ user1 ];
   }
   ```
3. Edit secret files (assuming your SSH private key is in ~/.ssh/):
   ```console
   $ agenix -e secret1.age
   ```
4. Add secret to NixOS module config:
   ```nix
   age.secrets.secret1.file = ../secrets/secret1.age;
   ```
5. NixOS rebuild or use your deployment too like usual.

## Rekeying

If you change the public keys in `secrets.nix`, you should rekey your
secrets:

```console
$ agenix --rekey
```

To rekey a secret, you have to be able to decrypt it. Because of
randomness in `age`'s encryption algorithms, the files always change
when rekeyed, even if the identities do not. This eventually could be
improved upon by reading the identities from the age file.

## Threat model/Warnings

This project has not be audited by a security professional.

People unfamiliar with `age` might be surprised that secrets are not
authenticated. This means that every attacker that has write access to
the repository can modify secrets because public keys are exposed.
This seems like not a problem on the first glance because changing the
configuration itself could expose secrets easily. However it is easier
to review configuration changes rather than random secrets (for
example 4096-bit rsa keys).  This would be solved by having a message
authentication code (MAC) like other implementations like GPG or
[sops](https://github.com/Mic92/sops-nix) have, however this was left
out for simplicity in `age`.

## Acknowledgements

This project is based off of
[sops-nix](https://github.com/Mic92/sops-nix) created Mic92. Thank you
to Mic92 for inspiration and help with making this.
