# Generating secrets before deployment {#generating-secrets}

[agenix-rekey](https://github.com/oddlama/agenix-rekey#secret-generation)
provides declarative generators for agenix secrets. Run generation on your
administration machine before building the target configuration. This lets
you bootstrap missing ciphertext while keeping private keys and random
plaintext out of Nix evaluation and build outputs.

Copy [the generation example](https://github.com/ryantm/agenix/blob/main/example/generation.nix)
into your configuration repository as `generation.nix`. It defines a random
API token and a reusable Ed25519 key generator. The token goes directly to
the encryption command; the SSH generator uses a private temporary directory
and removes it on exit. Its public key is saved beside the ciphertext as
`deploy-key.age.pub`. Choose a private `TMPDIR` on a RAM filesystem if you
need to avoid temporary plaintext on disk.

Add the extension and example to your existing flake, replacing the identity
path and both public keys with your own values:

```nix
{
  inputs = {
    nixpkgs.url = "github:NixOS/nixpkgs/nixos-26.05";
    agenix.url = "github:ryantm/agenix";
    agenix-rekey.url = "github:oddlama/agenix-rekey";
    agenix-rekey.inputs.nixpkgs.follows = "nixpkgs";
  };

  outputs = { self, nixpkgs, agenix, agenix-rekey }: {
    nixosConfigurations.machine = nixpkgs.lib.nixosSystem {
      system = "x86_64-linux";
      modules = [
        ./configuration.nix
        agenix.nixosModules.default
        agenix-rekey.nixosModules.default
        (import ./generation.nix {
          root = self.outPath;
          hostName = "machine";
          hostPublicKey = "ssh-ed25519 REPLACE_WITH_HOST_PUBLIC_KEY";
          masterIdentity = "/home/alice/.ssh/id_ed25519";
          masterPublicKey = "ssh-ed25519 REPLACE_WITH_ADMIN_PUBLIC_KEY";
        })
      ];
    };
    agenix-rekey = agenix-rekey.configure {
      userFlake = self;
      nixosConfigurations = self.nixosConfigurations;
    };
  };
}
```

Keep the administrator's private identity outside the store: `masterIdentity`
is an absolute runtime string. The target must already have the private
identity matching `hostPublicKey` in its `age.identityPaths`. Verify that
public key before encrypting anything to it. Keep each host's rekey output
directory separate.

From the flake repository, bootstrap and prepare the host ciphertext:

```sh
nix flake lock
git add flake.nix flake.lock generation.nix
nix run .#agenix-rekey.x86_64-linux.generate
git add secrets/
nix run .#agenix-rekey.x86_64-linux.rekey
git add secrets/
nixos-rebuild build --flake .#machine
```

Use your administration machine's architecture in these app paths. Inspect
and commit the ciphertext and public keys before deployment. Generation
creates the administrator-encrypted copies; rekeying creates the copies the
target can decrypt. With these independent generators, rerunning generation
preserves existing secrets. Explicit regeneration is a key rotation and
requires updating consumers and rekeying again.

These options and subcommands belong to **agenix-rekey**. Plain agenix does
not define `age.generate.enable` or an `agenix generate` command. For Home
Manager, import both projects' Home Manager modules and expose your
`homeConfigurations` through `agenix-rekey.configure`; the same generator
module works there. See the extension's documentation for dependencies
between generators and its built-in generators. Repository commits and
pushes remain explicit steps in this workflow.
