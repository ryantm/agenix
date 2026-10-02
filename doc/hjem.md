# Standalone Hjem {#standalone-hjem}

`agenix.lib.hjemConfiguration` produces a manifest and packages for
[standalone Hjem](https://github.com/feel-co/hjem/blob/main/docs/inputs/standalone.md). This integration
currently supports Linux with a running systemd user manager. It does not require
the NixOS agenix module or Home Manager.

Add an agenix input to your Hjem flake, then use the helper as a standalone
configuration:

```nix
{
  inputs.nixpkgs.url = "github:NixOS/nixpkgs/nixos-26.05";
  inputs.agenix.url = "github:ryantm/agenix";

  outputs = { nixpkgs, agenix, ... }: {
    hjemConfigurations.alice = agenix.lib.hjemConfiguration {
      pkgs = nixpkgs.legacyPackages.x86_64-linux;
      homeDirectory = "/home/alice";
      modules = [
        {
          age.identityPaths = [ "/home/alice/.ssh/id_ed25519" ];
          age.secrets.token.file = ./token.age;
        }
      ];
    };
  };
}
```

Encrypt `token.age` to the matching public recipient using the agenix CLI. Keep
private identity paths as absolute strings so Nix does not copy them to the
store. The identity must be available to the user service without an interactive
passphrase prompt.

Build the generated service and command, apply the configuration, then decrypt:

```sh
nix build ~/.config/hjem#hjemConfigurations.alice.packages --no-link
hjem standalone switch --flake ~/.config/hjem
~/.local/state/hjem/standalone/current-profile/bin/agenix-hjem-activate
```

Repeat the build step before switching to changed configuration. Current Hjem
evaluates manifests without building their generated source files before linking
them. The generated package contains both the service and the activation command,
so building `packages` prepares everything the manifest needs. For a plain Nix
configuration, use `nix build --file ./hjem.nix packages --no-link` before
`hjem standalone switch --config ./hjem.nix`.

Hjem currently links files and installs packages without running activation
hooks. Run `agenix-hjem-activate` after each switch or rollback; it reloads the
user service definition and waits for decryption to finish. Hjem's `build` command
does not decrypt secrets. On subsequent logins, the installed `agenix.service`
runs automatically through `default.target`. Other user units that need secrets
can use `Requires=agenix.service` and `After=agenix.service`.

The default public path is `/home/alice/.local/state/agenix/token`. It is a stable
symlink into `${XDG_RUNTIME_DIR}/agenix.d`, where the plaintext generations live.
Logging out of the final session removes those runtime files unless the user's
manager lingers. The encrypted inputs and activation scripts may be in the Nix
store; decrypted content is created only when the user service runs.

The helper accepts `configHome` and `stateHome` arguments for non-default XDG
directories. Keep these consistent with the user's login environment. Its
`modules` and `specialArgs` arguments work like other Nix module evaluations.
Within modules, the supported `age` options are `enable`, `package`, `verbosity`,
`validateSecrets`, `identityPaths`, `secretsDir`, `secretsMountPoint`, and `secrets`.
Secret options match the Home Manager module, including `path`, `mode`, `symlink`,
`enable`, and `trimFinalNewline`. Secrets belong to the invoking user.

To add agenix to an existing manifest, append the generated entries and packages:

```nix
let
  secrets = agenix.lib.hjemConfiguration {
    inherit pkgs;
    homeDirectory = "/home/alice";
    modules = [ ./secrets.nix ];
  };
in
{
  manifest = existing.manifest // {
    files = existing.manifest.files ++ secrets.manifest.files;
  };
  packages = (existing.packages or [ ]) ++ secrets.packages;
}
```

The existing manifest must use version 3. The helper also exposes each secret's
destination as `paths`, so `secrets.paths.token` can be referenced in other
configuration. Do not read that runtime path with `builtins.readFile` during
evaluation.

When removing this integration, stop the service with
`systemctl --user stop agenix.service`, switch to the configuration without its
manifest entries, and run `systemctl --user daemon-reload`. Existing plaintext
files remain until the user's runtime directory is removed; custom direct
destinations configured with `symlink = false` must be removed separately.
