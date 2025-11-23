# Reference {#reference}

## `age` module reference {#age-module-reference}

### `age.secrets`

`age.secrets` attrset of secrets. You always need to use this
configuration option. Defaults to `{}`.

### `age.secrets.<name>.file`

`age.secrets.<name>.file` is the path to the encrypted `.age` for this
secret. This is the only required secret option.

Example:

```nix
{
  age.secrets.monitrc.file = ../secrets/monitrc.age;
}
```

### `age.secrets.<name>.path`

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
    hashedPasswordFile = config.age.secrets.passwordfile-ryantm.path;
  };
}
```

#### builtins.readFile anti-pattern

```nix
{
  # Do not do this!
  config.password = builtins.readFile config.age.secrets.secret1.path;
}
```

This can cause the cleartext to be placed into the world-readable Nix
store. Instead, have your services read the cleartext path at runtime.

### `age.secrets.<name>.mode`

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

### `age.secrets.<name>.owner`

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

### `age.secrets.<name>.group`

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

### `age.secrets.<name>.symlink`

`age.secrets.<name>.symlink` is a boolean. If true (the default),
secrets are symlinked to `age.secrets.<name>.path`. If false, secerts
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

### `age.secrets.<name>.name`

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

### `age.ageBin`

`age.ageBin` the string of the path to the `age` binary. Usually, you
don't need to change this. Defaults to `age/bin/age`.

Overriding `age.ageBin` example:

```nix
{pkgs, ...}:{
    age.ageBin = "${pkgs.age}/bin/age";
}
```

### `age.identityPaths`

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

### `age.secretsDir`

`age.secretsDir` is the directory where secrets are symlinked to by
default.Usually, you don't need to change this. Defaults to
`/run/agenix`.

Overriding `age.secretsDir` example:

```nix
{
    age.secretsDir = "/run/keys";
}
```

### `age.secretsMountPoint`

`age.secretsMountPoint` is the directory where the secret generations
are created before they are symlinked. Usually, you don't need to
change this. Defaults to `/run/agenix.d`.


Overriding `age.secretsMountPoint` example:

```nix
{
    age.secretsMountPoint = "/run/secret-generations";
}
```

## agenix CLI reference {#agenix-cli-reference}

```
agenix - edit and rekey age secret files

agenix -e FILE [-i PRIVATE_KEY] [-j PLUGIN]
agenix -r [-i PRIVATE_KEY] [-j PLUGIN]

options:
-h, --help                show help
-e, --edit FILE           edits FILE using $EDITOR
-r, --rekey               re-encrypts all secrets with specified recipients
-d, --decrypt FILE        decrypts FILE to STDOUT
-i, --identity            identity to use when decrypting
-j PLUGIN                 decrypt using the data-less plugin PLUGIN
-v, --verbose             verbose output

FILE an age-encrypted file

PRIVATE_KEY a path to a private SSH key used to decrypt file

EDITOR environment variable of editor to use when editing FILE

If STDIN is not interactive, EDITOR will be set to "cp /dev/stdin"

RULES environment variable with path to Nix file specifying recipient public keys.
Defaults to './secrets.nix'
