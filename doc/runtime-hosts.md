# Runtime hosts file {#runtime-hosts-file}

NixOS [builds `networking.hostFiles` into `/etc/hosts`](https://github.com/NixOS/nixpkgs/blob/nixos-26.05/nixos/modules/config/networking.nix)
in the Nix store. An agenix
secret's `.path` is created during activation, so it cannot be an input to that
build. `builtins.readFile` cannot make the runtime file available during evaluation
either.

To keep a hosts file encrypted in the configuration repository, let agenix manage
the complete file and make `/etc/hosts` refer to its runtime path:

```nix
{ config, lib, ... }:
{
  age.secrets.hosts = {
    file = ./hosts.age;
    mode = "0444";
  };

  environment.etc."hosts".source = lib.mkForce config.age.secrets.hosts.path;
}
```

This replaces the generated hosts file, so include the usual localhost and
machine-name entries in the plaintext before encrypting it. For a machine named
`myhost` with domain `example.test`, for example:

```text
127.0.0.1 localhost
::1 localhost
127.0.0.2 myhost.example.test myhost
192.0.2.10 private.example.test
```

Adjust these entries to the machine's hostname, domain, and IPv6 configuration.
`networking.hosts`, `networking.extraHosts`, and `networking.hostFiles` no longer
contribute to this replacement file. Leave the secret at its default agenix path;
`environment.etc` manages the `/etc/hosts` symlink.

The `0444` mode lets ordinary applications resolve names. The entries are therefore
readable by local users after activation, while the repository and store contain
the encrypted input. Hosts files should not contain credentials. Permissions
such as `0777` are unnecessary and would allow other users to modify name resolution.

New activations update the generation selected by the symlink. Applications and
name-service caches may retain earlier lookups; their normal cache invalidation
rules still apply. To inspect the file directly, bypassing those caches, use
`getent -s files hosts private.example.test`.

This recipe applies after system activation. It does not supply hosts entries to
the initrd or to programs that run before secret decryption. It also assumes
agenix activation can access its identities without needing the encrypted hosts
entries to retrieve those identities.
