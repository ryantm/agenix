# Reference {#reference}

## `age` module reference {#age-module-reference}

### `age.enable`

`age.enable` controls whether agenix installs secrets and runs activation.
It defaults to true when at least one secret is enabled, and false otherwise.
Set it to false to disable the module even when secrets are configured.
Switching an existing system to `false` does not remove secrets already
decrypted in `/run`; reboot to clear them.

### `age.verbosity`

`age.verbosity` controls agenix's routine activation messages. It accepts
`"quiet"`, `"summary"`, `"progress"`, or `"detailed"` and defaults to
`"detailed"`, preserving the current output.

| Value | Messages |
| --- | --- |
| `"quiet"` | No routine agenix messages |
| `"summary"` | One decryption summary |
| `"progress"` | Summary and generation, linking, cleanup, and ownership steps |
| `"detailed"` | All of the above, plus one line per secret |

Warnings and errors remain visible at every level. The Home Manager module
uses the same levels, without an ownership step. This option does not control
output from Nix, systemd, other activation scripts, or the `agenix` CLI.
The CLI's `-v` option enables shell tracing independently of this setting.

### `age.secrets`

`age.secrets` attrset of secrets. You always need to use this
configuration option. Defaults to `{}`.

### `age.secrets.<name>.enable`

`age.secrets.<name>.enable` defaults to true. Set it to false to omit that
secret from the installed generation. A disabled secret does not need a
`file` value.

### `age.secrets.<name>.file`

`age.secrets.<name>.file` is the path to the encrypted `.age` for this
secret. This is required for enabled secrets.

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

## Home Manager module reference {#home-manager-module-reference}

The Home Manager module manages secrets for one user. Its options are separate
from the NixOS module options above, even where they share a name.

### `age.enable`

Defaults to true when at least one secret is enabled. Set it to false to
disable the Home Manager agenix service. Disabling the service does not remove
secrets decrypted by earlier activations.

### `age.verbosity`

Accepts the same four levels described above and defaults to `"detailed"`.
There is no ownership step in the Home Manager service. Warnings and errors
remain visible at every level.

### `age.package`

The `age` package used to decrypt secrets. Defaults to `pkgs.age`.

### `age.secrets`

An attribute set of secrets. Defaults to `{}`.

### `age.secrets.<name>.enable`

Defaults to true. Set it to false to omit the secret; a disabled secret does
not need a `file` value.

### `age.secrets.<name>.file`

The path to the encrypted `.age` file. Required for enabled secrets.

### `age.secrets.<name>.name`

The decrypted file's name under `age.secretsDir`. Defaults to `<name>` from
the attribute path.

### `age.secrets.<name>.path`

The destination of the decrypted secret. Defaults to
`config.age.secretsDir/<name>`, which is usually
`$XDG_RUNTIME_DIR/agenix/<name>` on Linux or
`$(getconf DARWIN_USER_TEMP_DIR)/agenix/<name>` on Darwin.

### `age.secrets.<name>.mode`

Permissions of the decrypted secret in a format understood by `chmod`.
Defaults to `"0400"`.

### `age.secrets.<name>.symlink`

Defaults to true. If true, the destination is a symlink to the current secret
generation. If false, the decrypted file is copied to its destination; you
are then responsible for removing it when no longer needed.

### `age.identityPaths`

Paths to SSH private keys to try for decryption. By default, the module tries
`<home>/.ssh/id_ed25519` and `<home>/.ssh/id_rsa`, using
`config.home.homeDirectory` for `<home>`. At least one readable identity must
be available when secrets are decrypted. Use strings containing absolute paths
when overriding this option; a Nix path would copy the private key into the
world-readable Nix store.

### `age.secretsDir`

Directory where secrets are exposed. Defaults to `$XDG_RUNTIME_DIR/agenix`
on Linux and `$(getconf DARWIN_USER_TEMP_DIR)/agenix` on Darwin.

### `age.secretsMountPoint`

Directory where generations are created before they are linked. Defaults to
`$XDG_RUNTIME_DIR/agenix.d` on Linux and
`$(getconf DARWIN_USER_TEMP_DIR)/agenix.d` on Darwin.

## agenix CLI reference {#agenix-cli-reference}

The CLI evaluates your local rules file with impure evaluation enabled, even
when `pure-eval = true` is set in `nix.conf`. This allows it to read the selected
file and any local files imported by those rules.

Select one operation per invocation: edit, decrypt, rekey, or check. Each command
evaluates the rules it needs once. Editing or decrypting a single file does not
evaluate unrelated secrets, and checking or decrypting does not evaluate armor
settings. Secret filenames are literal rule names and may contain spaces or
quotes. Relative filenames resolve from the selected rules file's directory.

```
agenix - edit, rekey, and check age secret files

agenix -e FILE [-i PRIVATE_KEY] [-j PLUGIN]
agenix -r [PUBLIC_KEY] [-i PRIVATE_KEY] [-j PLUGIN]
agenix -c

options:
-h, --help                show help
-e, --edit FILE           edits FILE using $EDITOR
-r, --rekey [PUBLIC_KEY]  re-encrypts secrets, optionally selecting a recipient
-c, --check               checks encrypted SSH recipients against the rules
-d, --decrypt FILE        decrypts FILE to STDOUT
-i, --identity            identity to use when decrypting
-j PLUGIN                 decrypt using the data-less plugin PLUGIN
-v, --verbose             verbose output

FILE an age-encrypted file

PRIVATE_KEY a path to a private SSH key used to decrypt file

PUBLIC_KEY an exact public key string from the rules; only matching secrets are rekeyed

EDITOR environment variable of editor to use when editing FILE

If STDIN is not interactive, its contents replace the secret.
Piped input replaces a secret without decrypting it first.

AGENIX_RULES environment variable with path to Nix file specifying recipient public keys. 
Searches the current directory for agenix-rules.nix, then secrets.nix.
Searches parent directories for agenix-rules.nix only.
Resolves relative secret paths from the selected rules file's directory.
```

`-j PLUGIN` passes a data-less plugin identity to age for decryption, editing,
or rekeying. The corresponding `age-plugin-PLUGIN` executable must be on
`PATH`. No private key file is needed; supplying `-j` also disables automatic
discovery of `~/.ssh/id_rsa` and `~/.ssh/id_ed25519`. Encryption still uses
the recipients in the rules file.

`agenix --check` compares the SSH recipient tags in each age file header with
the public keys in the rules file. It prints `✓` for matching files and `✗`
with missing or extra recipients for mismatches, and exits with a nonzero status
if any file differs or cannot be checked. It does not decrypt or change files,
so no private key is needed. Age's SSH tags are 32-bit identifiers; this check
shows a full extra key when it can find a matching key literal in the rules
file, and otherwise shows the tag. It cannot verify native age recipients or
authenticate the encrypted contents.

> [!WARNING]
> The legacy `RULES` environment variable and automatic discovery of
> `secrets.nix` still work, but agenix warns when either is used. Both will be
> removed in a future version. Explicitly selecting `secrets.nix` with
> `AGENIX_RULES` does not warn.
