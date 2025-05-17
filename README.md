# agenix - [age](https://github.com/FiloSottile/age)-encrypted secrets for NixOS

`agenix` is a small and convenient Nix library for securely managing and deploying secrets using common public-private SSH key pairs:
You can encrypt a secret (password, access-token, etc.) on a source machine using a number of public SSH keys,
and deploy that encrypted secret to any another target machine that has the corresponding private SSH key of one of those public keys.
This project contains two parts:
1. An `agenix` commandline app (CLI) to encrypt secrets into secured `.age` files that can be copied into the Nix store.
2. An `agenix` NixOS module to conveniently
    * add those encrypted secrets (`.age` files) into the Nix store so that they can be deployed like any other Nix package using `nixos-rebuild` or similar tools.
    * automatically decrypt on a target machine using the private SSH keys on that machine
    * automatically mount these decrypted secrets on a well known path like `/run/agenix/...` to be consumed.

## Contents

* [Problem and solution](#problem-and-solution)
* [Features](#features)
* [Installation](#installation)
  * [niv](#install-via-niv)
  * [nix-channel](#install-via-nix-channel)
  * [fetchTarball](#install-via-fetchtarball)
  * [flakes](#install-via-flakes)
* [Tutorial](#tutorial)
* [Reference](#reference)
  * [`age` module reference](#age-module-reference)
  * [`age-home` module reference](#age-home-module-reference)
  * [agenix CLI reference](#agenix-cli-reference)
* [Community and Support](#community-and-support)
* [Threat model/Warnings](#threat-modelwarnings)
* [Contributing](#contributing)
* [Acknowledgements](#acknowledgements)

## Problem and solution

All files in the Nix store are readable by any system user, so it is not a suitable place for including cleartext secrets. Many existing tools (like NixOps deployment.keys) deploy secrets separately from `nixos-rebuild`, making deployment, caching, and auditing more difficult. Out-of-band secret management is also less reproducible.

`agenix` solves these issues by using your pre-existing SSH key infrastructure and `age` to encrypt secrets into the Nix store. Secrets are decrypted using an SSH host private key during NixOS system activation.

## Features

* Secrets are encrypted with SSH keys
  * system public keys via `ssh-keyscan`
  * can use public keys available on GitHub for users (for example, https://github.com/ryantm.keys)
* No GPG
* Very little code, so it should be easy for you to audit
* Encrypted secrets are stored in the Nix store, so a separate distribution mechanism is not necessary

## Notices

* Password-protected ssh keys: since age does not support ssh-agent, password-protected ssh keys do not work well. For example, if you need to rekey 20 secrets you will have to enter your password 20 times.

## Installation

<details>
<summary>

### Install via [niv](https://github.com/nmattia/niv)

</summary>

First add it to niv:

```ShellSession
$ niv add ryantm/agenix
```

#### Install module via niv

Then add the following to your `configuration.nix` in the `imports` list:

```nix
{
  imports = [ "${(import ./nix/sources.nix).agenix}/modules/age.nix" ];
}
```

#### Install home-manager module via niv

Add the following to your home configuration:

```nix
{
  imports = [ "${(import ./nix/sources.nix).agenix}/modules/age-home.nix" ];
}
```

#### Install CLI via niv

To install the `agenix` binary:

```nix
{
  environment.systemPackages = [ (pkgs.callPackage "${(import ./nix/sources.nix).agenix}/pkgs/agenix.nix" {}) ];
}
```

</details>

<details>
<summary>

### Install via nix-channel

</summary>

As root run:

```ShellSession
$ sudo nix-channel --add https://github.com/ryantm/agenix/archive/main.tar.gz agenix
$ sudo nix-channel --update
```

#### Install module via nix-channel

Then add the following to your `configuration.nix` in the `imports` list:

```nix
{
  imports = [ <agenix/modules/age.nix> ];
}
```

#### Install home-manager module via nix-channel

Add the following to your home configuration:

```nix
{
  imports = [ <agenix/modules/age-home.nix> ];
}
```

#### Install CLI via nix-channel

To install the `agenix` binary:

```nix
{
  environment.systemPackages = [ (pkgs.callPackage <agenix/pkgs/agenix.nix> {}) ];
}
```

</details>

<details>
<summary>

### Install via fetchTarball

</summary>

#### Install module via fetchTarball

Add the following to your configuration.nix:

```nix
{
  imports = [ "${builtins.fetchTarball "https://github.com/ryantm/agenix/archive/main.tar.gz"}/modules/age.nix" ];
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
      # update hash from nix build output
      sha256 = "";
    }}/modules/age.nix"
  ];
}
```

#### Install home-manager module via fetchTarball

Add the following to your home configuration:

```nix
{
  imports = [ "${builtins.fetchTarball "https://github.com/ryantm/agenix/archive/main.tar.gz"}/modules/age-home.nix" ];
}
```

Or with pinning:

```nix
{
  imports = let
    # replace this with an actual commit id or tag
    commit = "298b235f664f925b433614dc33380f0662adfc3f";
  in [
    "${builtins.fetchTarball {
      url = "https://github.com/ryantm/agenix/archive/${commit}.tar.gz";
      # update hash from nix build output
      sha256 = "";
    }}/modules/age-home.nix"
  ];
}
```

#### Install CLI via fetchTarball

To install the `agenix` binary:

```nix
{
  environment.systemPackages = [ (pkgs.callPackage "${builtins.fetchTarball "https://github.com/ryantm/agenix/archive/main.tar.gz"}/pkgs/agenix.nix" {}) ];
}
```

</details>

<details>
<summary>

### Install via Flakes

</summary>

#### Install module via Flakes

```nix
{
  inputs.agenix.url = "github:ryantm/agenix";
  # optional, not necessary for the module
  #inputs.agenix.inputs.nixpkgs.follows = "nixpkgs";
  # optionally choose not to download darwin deps (saves some resources on Linux)
  #inputs.agenix.inputs.darwin.follows = "";

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

#### Install home-manager module via Flakes

```nix
{
  inputs.agenix.url = "github:ryantm/agenix";

  outputs = { self, nixpkgs, agenix, home-manager }: {
    homeConfigurations."username" = home-manager.lib.homeManagerConfiguration {
      # ...
      modules = [
        agenix.homeManagerModules.default
        # ...
      ];
    };
  };
}
```

#### Install CLI via Flakes

You can run the CLI tool ad-hoc without installing it:

```ShellSession
nix run github:ryantm/agenix -- --help
```

But you can also add it permanently into a [NixOS module](https://wiki.nixos.org/wiki/NixOS_modules)
(replace system "x86_64-linux" with your system):

```nix
{
  environment.systemPackages = [ agenix.packages.x86_64-linux.default ];
}
```

e.g. inside your `flake.nix` file:

```nix
{
  inputs.agenix.url = "github:ryantm/agenix";
  # ...

  outputs = { self, nixpkgs, agenix }: {
    # change `yourhostname` to your actual hostname
    nixosConfigurations.yourhostname = nixpkgs.lib.nixosSystem {
      system = "x86_64-linux";
      modules = [
        # ...
        {
          environment.systemPackages = [ agenix.packages.${system}.default ];
        }
      ];
    };
  };
}
```

</details>

## Tutorial

1. The system you want to deploy secrets to should already exist and
   have `sshd` running on it so that it has generated SSH host keys in
   `/etc/ssh/`.

2. Make a directory to store secrets and `secrets.nix` file for listing secrets and their public keys:
   ```ShellSession
   $ mkdir secrets
   $ cd secrets
   $ touch secrets.nix
   ```
   This `secrets.nix` file is **not** imported into your NixOS configuration.
   It's only used for the `agenix` CLI tool (example below) to know which public keys to use for encryption.
3. Add public keys to your `secrets.nix` file:
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
   }
   ```
   These are the users and systems that will be able to decrypt the `.age` files later with their corresponding private keys.
   You can obtain the public keys from
   * your local computer usually in `~/.ssh`, e.g. `~/.ssh/id_ed25519.pub`.
   * from a running target machine with `ssh-keyscan`:
     ```ShellSession
     $ ssh-keyscan <ip-address>
     ... ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAIKzxQgondgEYcLpcPdJLrTdNgZ2gznOHCAxMdaceTUT1
     ...
     ```
   * from GitHub like https://github.com/ryantm.keys.
4. Create a secret file:
   ```ShellSession
   $ agenix -e secret1.age
   ```
   It will open a temporary file in the app configured in your $EDITOR environment variable.
   When you save that file its content will be encrypted with all the public keys mentioned in the `secrets.nix` file.
5. Add secret to a NixOS module config:
   ```nix
   {
     age.secrets.secret1.file = ../secrets/secret1.age;
   }
   ```
   When the `age.secrets` attribute set contains a secret, the `agenix` NixOS module will later automatically decrypt and mount that secret under the default path `/run/agenix/secret1`.
   Here the `secret1.age` file becomes part of your NixOS deployment, i.e. moves into the Nix store.

6. Reference the secrets' mount path in your config:
   ```nix
   {
     users.users.user1 = {
       isNormalUser = true;
       passwordFile = config.age.secrets.secret1.path;
     };
   }
   ```
   You can reference the mount path to the (later) unencrypted secret already in your other configuration.
   So `config.age.secrets.secret1.path` will contain the path `/run/agenix/secret1` by default.
7. Use `nixos-rebuild` or [another deployment tool](https://nixos.wiki/wiki/Applications#Deployment") of choice as usual.

   The `secret1.age` file will be copied over to the target machine like any other Nix package.
   Then it will be decrypted and mounted as described before.
8. Edit secret files:
   ```ShellSession
   $ agenix -e secret1.age
   ```
   It assumes your SSH private key is in `~/.ssh/`.
   In order to decrypt and open a `.age` file for editing you need the private key of one of the public keys
   it was encrypted with. You can pass the private key you want to use explicitly with `-i`, e.g.
   ```ShellSession
   $ agenix -e secret1.age -i ~/.ssh/id_ed25519
   ```

### Using agenix with home-manager

The home-manager module follows the same general principles as the NixOS module but is scoped to a single user. Here's how to use it:

1. Add the home-manager module to your configuration as shown in the Installation section.
2. Define your SSH identities and secrets:

```nix
{
  age = {
    identityPaths = [ "~/.ssh/id_ed25519" ];
    secrets = {
      example-secret = {
        file = ../secrets/example-secret.age;
      };
    };
  };
}
```

3. Reference your secrets in your home configuration:

```nix
{
  programs.some-program = {
    enable = true;
    passwordFile = config.age.secrets.example-secret.path;
  };
}
```

When you run `home-manager switch`, your secrets will be decrypted to a user-specific directory (usually `$XDG_RUNTIME_DIR/agenix` on Linux or a temporary directory on Darwin) and can be referenced in your configuration.

## Reference

### `age` module reference

#### `age.secrets`

`age.secrets` attrset of secrets. You always need to use this
configuration option. Defaults to `{}`.

#### `age.secrets.<name>.file`

`age.secrets.<name>.file` is the path to the encrypted `.age` for this
secret. This is the only required secret option.

Example:

```nix
{
  age.secrets.monitrc.file = ../secrets/monitrc.age;
}
```

#### `age.secrets.<name>.path`

`age.secrets.<name>.path` is the path where the secret is decrypted
to. Defaults to `/run/agenix/<name>` (`config.age.secretsDir/<name>`).

Example defining a different path:

```nix
{
  age.secrets.monitrc = {
    file = ../secrets/monitrc.age;
    path = "/etc/monitrc";
  };
}
```

For many services, you do not need to set this. Instead, refer to the
decryption path in your configuration with
`config.age.secrets.<name>.path`.

Example referring to path:

```nix
{
  users.users.ryantm = {
    isNormalUser = true;
    passwordFile = config.age.secrets.passwordfile-ryantm.path;
  };
}
```

##### builtins.readFile anti-pattern

```nix
{
  # Do not do this!
  config.password = builtins.readFile config.age.secrets.secret1.path;
}
```

This can cause the cleartext to be placed into the world-readable Nix
store. Instead, have your services read the cleartext path at runtime.

#### `age.secrets.<name>.mode`

`age.secrets.<name>.mode` is permissions mode of the decrypted secret
in a format understood by chmod. Usually, you only need to use this in
combination with `age.secrets.<name>.owner` and
`age.secrets.<name>.group`

Example:

```nix
{
  age.secrets.nginx-htpasswd = {
    file = ../secrets/nginx.htpasswd.age;
    mode = "770";
    owner = "nginx";
    group = "nginx";
  };
}
```

#### `age.secrets.<name>.owner`

`age.secrets.<name>.owner` is the username of the decrypted file's
owner. Usually, you only need to use this in combination with
`age.secrets.<name>.mode` and `age.secrets.<name>.group`

Example:

```nix
{
  age.secrets.nginx-htpasswd = {
    file = ../secrets/nginx.htpasswd.age;
    mode = "770";
    owner = "nginx";
    group = "nginx";
  };
}
```

#### `age.secrets.<name>.group`

`age.secrets.<name>.group` is the name of the decrypted file's
group. Usually, you only need to use this in combination with
`age.secrets.<name>.owner` and `age.secrets.<name>.mode`

Example:

```nix
{
  age.secrets.nginx-htpasswd = {
    file = ../secrets/nginx.htpasswd.age;
    mode = "770";
    owner = "nginx";
    group = "nginx";
  };
}
```

#### `age.secrets.<name>.symlink`

`age.secrets.<name>.symlink` is a boolean. If true (the default),
secrets are symlinked to `age.secrets.<name>.path`. If false, secrets
are copied to `age.secrets.<name>.path`. Usually, you want to keep
this as true, because it secure cleanup of secrets no longer
used. (The symlink will still be there, but it will be broken.) If
false, you are responsible for cleaning up your own secrets after you
stop using them.

Some programs do not like following symlinks (for example Java
programs like Elasticsearch).

Example:

```nix
{
  age.secrets."elasticsearch.conf" = {
    file = ../secrets/elasticsearch.conf.age;
    symlink = false;
  };
}
```

#### `age.secrets.<name>.name`

`age.secrets.<name>.name` is the string of the name of the file after
it is decrypted. Defaults to the `<name>` in the attrpath, but can be
set separately if you want the file name to be different from the
attribute name part.

Example of a secret with a name different from its attrpath:

```nix
{
  age.secrets.monit = {
    name = "monitrc";
    file = ../secrets/monitrc.age;
  };
}
```

#### `age.ageBin`

`age.ageBin` the string of the path to the `age` binary. Usually, you
don't need to change this. Defaults to `age/bin/age`.

Overriding `age.ageBin` example:

```nix
{pkgs, ...}:{
    age.ageBin = "${pkgs.age}/bin/age";
}
```

#### `age.identityPaths`

`age.identityPaths` is a list of paths to recipient keys to try to use to
decrypt the secrets. By default, it is the `rsa` and `ed25519` keys in
`config.services.openssh.hostKeys`, and on NixOS you usually don't need to
change this. The list items should be strings (`"/path/to/id_rsa"`), not
nix paths (`../path/to/id_rsa`), as the latter would copy your private key to
the nix store, which is the exact situation `agenix` is designed to avoid. At
least one of the file paths must be present at runtime and able to decrypt the
secret in question. Overriding `age.identityPaths` example:

```nix
{
    age.identityPaths = [ "/var/lib/persistent/ssh_host_ed25519_key" ];
}
```

#### `age.secretsDir`

`age.secretsDir` is the directory where secrets are symlinked to by
default. Usually, you don't need to change this. Defaults to
`/run/agenix`.

Overriding `age.secretsDir` example:

```nix
{
    age.secretsDir = "/run/keys";
}
```

#### `age.secretsMountPoint`

`age.secretsMountPoint` is the directory where the secret generations
are created before they are symlinked. Usually, you don't need to
change this. Defaults to `/run/agenix.d`.


Overriding `age.secretsMountPoint` example:

```nix
{
    age.secretsMountPoint = "/run/secret-generations";
}
```

### `age-home` module reference

The home-manager module provides options similar to the NixOS module but scoped to a single user.

#### `age.secrets`

`age.secrets` attrset of secrets. You always need to use this
configuration option. Defaults to `{}`.

#### `age.secrets.<name>.file`

`age.secrets.<name>.file` is the path to the encrypted `.age` for this
secret. This is the only required secret option.

#### `age.secrets.<name>.path`

`age.secrets.<name>.path` is the path where the secret is decrypted
to. Defaults to `$XDG_RUNTIME_DIR/agenix/<name>` on Linux and
`$(getconf DARWIN_USER_TEMP_DIR)/agenix/<name>` on Darwin.

#### `age.secrets.<name>.mode`

`age.secrets.<name>.mode` is permissions mode of the decrypted secret
in a format understood by chmod.

#### `age.secrets.<name>.symlink`

`age.secrets.<name>.symlink` is a boolean. If true (the default),
secrets are symlinked to `age.secrets.<name>.path`. If false, secrets
are copied to `age.secrets.<name>.path`.

#### `age.identityPaths`

`age.identityPaths` is a list of paths to SSH private keys to use for decryption.
This is a required option; there is no default value.

#### `age.secretsDir`

`age.secretsDir` is the directory where secrets are symlinked to by
default. Defaults to `$XDG_RUNTIME_DIR/agenix` on Linux and
`$(getconf DARWIN_USER_TEMP_DIR)/agenix` on Darwin.

#### `age.secretsMountPoint`

`age.secretsMountPoint` is the directory where the secret generations
are created before they are symlinked. Defaults to `$XDG_RUNTIME_DIR/agenix.d`
on Linux and `$(getconf DARWIN_USER_TEMP_DIR)/agenix.d` on Darwin.

### agenix CLI reference

```
agenix - edit and rekey age secret files

agenix -e FILE [-i PRIVATE_KEY]
agenix -r [-i PRIVATE_KEY]

options:
-h, --help                show help
-e, --edit FILE           edits FILE using $EDITOR
-r, --rekey               re-encrypts all secrets with specified recipients
-d, --decrypt FILE        decrypts FILE to STDOUT
-i, --identity            identity to use when decrypting
-v, --verbose             verbose output

FILE an age-encrypted file

PRIVATE_KEY a path to a private SSH key used to decrypt file

EDITOR environment variable of editor to use when editing FILE

If STDIN is not interactive, EDITOR will be set to "cp /dev/stdin"

RULES environment variable with path to Nix file specifying recipient public keys.
Defaults to './secrets.nix'
```

#### Rekeying

If you change the public keys in `secrets.nix`, you should rekey your
secrets:

```ShellSession
$ agenix --rekey
```

To rekey a secret, you have to be able to decrypt it. Because of
randomness in `age`'s encryption algorithms, the files always change
when rekeyed, even if the identities do not. (This eventually could be
improved upon by reading the identities from the age file.)

#### Overriding age binary

The agenix CLI uses `age` by default as its age implemenation, you
can use the `rage` implementation with Flakes like this:

```nix
{pkgs,agenix,...}:{
  environment.systemPackages = [
    (agenix.packages.x86_64-linux.default.override { ageBin = "${pkgs.rage}/bin/rage"; })
  ];
}
```

## Community and Support

Support and development discussion is available here on GitHub and
also through [Matrix](https://matrix.to/#/#agenix:nixos.org).

## Threat model/Warnings

This project has not been audited by a security professional.

People unfamiliar with `age` might be surprised that secrets are not
authenticated. This means that every attacker that has write access to
the secret files can modify secrets because public keys are exposed.
This seems like not a problem on the first glance because changing the
configuration itself could expose secrets easily. However, reviewing
configuration changes is easier than reviewing random secrets (for
example, 4096-bit rsa keys). This would be solved by having a message
authentication code (MAC) like other implementations like GPG or
[sops](https://github.com/Mic92/sops-nix) have, however this was left
out for simplicity in `age`.

Additionally you should only encrypt secrets that you are able to make useless in the event that they are decrypted in the future and be ready to rotate them periodically as [age](https://github.com/FiloSottile/age) is [as of 19th June 2024 NOT Post-Quantum Safe](https://github.com/FiloSottile/age/discussions/231#discussioncomment-3092773) and so in case the threat actor can access your encrypted keys e.g. via their use in a public repository then they can utilize the strategy of [Harvest Now, Decrypt Later](https://en.wikipedia.org/wiki/Harvest_now,_decrypt_later) to store your keys now for later decryption including the case where a major vulnerability is found that would expose the secrets. See https://github.com/FiloSottile/age/issues/578 for details.

## Contributing

* The main branch is protected against direct pushes
* All changes must go through GitHub PR review and get at least one approval
* PR titles and commit messages should be prefixed with at least one of these categories:
  * contrib - things that make the project development better
  * doc - documentation
  * feature - new features
  * fix - bug fixes
* Please update or make integration tests for new features
* Use `nix fmt` to format nix code


### Tests

You can run the tests with

```ShellSession
nix flake check
```

You can run the integration tests in interactive mode like this:

```ShellSession
nix run .#checks.x86_64-linux.integration.driverInteractive
```

After it starts, enter `run_tests()` to run the tests.

## Acknowledgements

This project is based off of [sops-nix](https://github.com/Mic92/sops-nix) created Mic92. Thank you to Mic92 for inspiration and advice.
