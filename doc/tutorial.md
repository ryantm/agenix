# Tutorial {#tutorial}

This walkthrough uses SSH keys and keeps encrypted secrets alongside your
Nix configuration. The layout is a convention: the modules accept encrypted
files at any configured path and do not require a `secrets` directory.

1. The target system needs an SSH host key pair. A system with `sshd`
   enabled normally generates these in `/etc/ssh/`. Obtain its public key
   for encryption; keep the private key on the target.

2. On the machine where you edit secrets, start in your configuration
   repository and create a directory for encrypted files and CLI rules:

   ```ShellSession
   $ mkdir secrets
   $ cd secrets
   $ touch agenix-rules.nix
   ```

   `agenix-rules.nix` contains public keys and filenames. It is CLI input,
   not a NixOS module, so do not add it to your module's `imports`. Both the
   rules and encrypted `.age` files can be committed to Git. Keep private
   identities and plaintext outside the repository and the Nix store.

   By default, run the CLI from this directory. To select another rules
   file explicitly, set `AGENIX_RULES`; see the [CLI reference](#agenix-cli-reference).
3. Add public keys to `agenix-rules.nix` file (hint: use `ssh-keyscan` or GitHub (for example, https://github.com/ryantm.keys)):
   ```nix
   let
     user1 = "ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAIL0idNvgGiucWgup/mP78zyC23uFjYq0evcWdjGQUaBH";
     user2 = "ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAILI6jSq53F/3hEmSs+oq9L4TwOo1PrDMAgcA1uo1CCV/";
     users = [ user1 user2 ];

     system1 = "ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAIPJDyIr/FSz1cJdcoW69R+NrWzwGK/+3gJpqD1t8L2zE";
     system2 = "ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAIKzxQgondgEYcLpcPdJLrTdNgZ2gznOHCAxMdaceTUT1";
     systems = [ system1 system2 ];
   in
   {
     "secret1.age".publicKeys = [ user1 system1 ];
     "secret2.age".publicKeys = users ++ systems;
     "armored-secret.age" = {
       publicKeys = [ user1 ];
       armor = true;
     };
   }
   ```
   The keys can come from `~/.ssh/id_ed25519.pub`, from a running target
   machine with `ssh-keyscan -t ed25519 <hostname-or-ip-address>`, or from
   a user's GitHub keys page. Each recipient needs the corresponding private
   key to decrypt the secret. The optional `armor = true` rule produces
   Base64 text, which can make diffs easier to read.
4. Edit secret files (these instructions assume your SSH private key is in ~/.ssh/):
   ```ShellSession
   $ agenix -e secret1.age
   ```
   You can also pipe complete contents into `agenix -e secret1.age` to create
   or replace a secret without a decryption key. This overwrites the previous
   contents rather than editing them.

   ```ShellSession
   $ printf '%s\n' 'new secret' | agenix -e secret1.age
   ```

   To edit an existing secret with a key outside `~/.ssh`, pass it explicitly:

   ```ShellSession
   $ agenix -e secret1.age -i /path/to/id_ed25519
   ```
5. In `configuration.nix` at the repository root, declare the encrypted file:
   ```nix
   {
     age.secrets.secret1.file = ./secrets/secret1.age;
   }
   ```
   For a Git-backed flake, add the encrypted file and rules to Git so they
   are included in the flake source. Paths in Nix are relative to the Nix
   file containing them, not the CLI's working directory.
6. Use the secret in your config:
   ```nix
   {
     users.users.user1 = {
       isNormalUser = true;
       hashedPasswordFile = config.age.secrets.secret1.path;
     };
   }
   ```
   In this password example, the encrypted file must contain a password
   hash suitable for `hashedPasswordFile`. For other consumers, encrypt
   the contents expected by their secret-file option.
7. NixOS rebuild or use your deployment tool like usual.

   The secret will be decrypted to the value of `config.age.secrets.secret1.path` (`/run/agenix/secret1` by default).

   A remote builder needs only the encrypted file. Nix copies it into the
   store and includes it in the target's system closure; the target does not
   need a checkout of your configuration repository. Provision its private
   identity separately at an `age.identityPaths` location before activation.

## Encrypting without the agenix CLI {#encrypting-with-age}

The deployment modules accept files created directly with `age`. For example,
encrypt an existing plaintext file for a target and an editor:

```ShellSession
$ age -R target-host.pub -R editor.pub -o secrets/service.age /secure/path/service.txt
```

Then declare `age.secrets.service.file = ./secrets/service.age;` in your
configuration. No CLI rules file is needed for this workflow. The target's
configured private identity must match one of the encryption recipients.

## Identity types {#identity-types}

Native age recipients (`age1...`) and identity files containing
`AGE-SECRET-KEY-...` are supported. Put the recipient string in a CLI rule's
`publicKeys` list, and explicitly set the private identity path on the target:

```nix
{
  age.identityPaths = [ "/var/lib/agenix/identity.txt" ];
}
```

For CLI edits with a native identity, use `agenix -e service.age -i
/secure/path/identity.txt`. Automatic identity discovery uses SSH key paths;
it does not find a native age identity stored elsewhere.

For SSH identities, age supports RSA and Ed25519 keys. ECDSA SSH keys and GPG
keys are not interchangeable with those supported identity types. See
[age's documentation](https://github.com/FiloSottile/age#ssh-keys) for SSH
support, or use a native identity generated with `age-keygen`.

## When decryption runs {#decryption-timing}

On NixOS, the default activation path decrypts secrets after `specialfs` and
before user creation, allowing secrets to supply user password hashes.
Ownership is assigned after users and groups exist. Systems using sysusers
or userborn perform these steps with the `agenix-install-secrets` and
`agenix-chown` system services. Identities and their backing filesystem must
be available when installation runs.

The nix-darwin module uses a system launchd daemon. Home Manager uses a user
systemd service on Linux and a user launchd agent on macOS. Those user-scoped
secrets are for applications in the user's session, not for NixOS user
creation or evaluation of Nix expressions.

## Using agenix with Home Manager

The Home Manager module follows the same approach for secrets scoped to one
user. Install the [Home Manager module](#install-via-flakes), then declare a secret:

```nix
{
  age.secrets.example-secret.file = ../secrets/example-secret.age;
}
```

The module tries your `~/.ssh/id_ed25519` and `~/.ssh/id_rsa` keys by default.
Set `age.identityPaths` to absolute paths if your keys are elsewhere. Use
`config.age.secrets.example-secret.path` for an application option that accepts
a secret file path.

After `home-manager switch`, secrets are available under
`$XDG_RUNTIME_DIR/agenix` on Linux or the Darwin user temporary directory by
default. See the [Home Manager module reference](#home-manager-module-reference)
for its options.
