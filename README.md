# agenix: age-encrypted secrets for NixOS and Home Manager

[Read the documentation](https://ryantm.github.io/agenix/).

`agenix` encrypts secrets with SSH public keys so the encrypted files can be
stored and deployed with Nix. Its CLI creates and rekeys `.age` files; the
NixOS and Home Manager modules decrypt them at activation time for the
intended machine or user.

## Quick start

Add the NixOS module to your flake:

```nix
{
  inputs.nixpkgs.url = "github:NixOS/nixpkgs/nixos-26.05";
  inputs.agenix.url = "github:ryantm/agenix";

  outputs = { nixpkgs, agenix, ... }: {
    nixosConfigurations.my-host = nixpkgs.lib.nixosSystem {
      system = "x86_64-linux";
      modules = [ agenix.nixosModules.default ./configuration.nix ];
    };
  };
}
```

In a secrets directory, create `agenix-rules.nix` listing the public SSH keys
allowed to decrypt each file. Then run
`nix run github:ryantm/agenix -- -e example.age` to create an encrypted
secret. Declare it in a NixOS module:

```nix
{
  age.secrets.example.file = ./secrets/example.age;
  # Use config.age.secrets.example.path wherever a service expects a secret file.
}
```

The [tutorial](https://ryantm.github.io/agenix/tutorial/) shows a complete rules file, key discovery,
installation, and deployment.

## Documentation

- [Installation](https://ryantm.github.io/agenix/install-via-flakes/) by flakes, [niv](https://ryantm.github.io/agenix/install-via-niv/), [nix-channel](https://ryantm.github.io/agenix/install-via-nix-channel/), or [fetchTarball](https://ryantm.github.io/agenix/install-via-fetchtarball/), including Home Manager installation.
- [NixOS module reference](https://ryantm.github.io/agenix/reference/#age-module-reference), [Home Manager module reference](https://ryantm.github.io/agenix/reference/#home-manager-module-reference), and [CLI reference](https://ryantm.github.io/agenix/reference/#agenix-cli-reference).
- [Threat model and warnings](https://ryantm.github.io/agenix/threat-model-warnings/) and [contributing and tests](https://ryantm.github.io/agenix/contributing/).

For help, use [GitHub issues](https://github.com/ryantm/agenix/issues) or
[Matrix](https://matrix.to/#/#agenix:nixos.org).
