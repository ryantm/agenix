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

### `age.cacheDecryption`

On NixOS and nix-darwin, `age.cacheDecryption` defaults to `true`. When the
configuration, encrypted files, public templates, local identity files, and
installed secrets are unchanged, activation reuses the current generation.
It skips decryption, template rendering, publication, and change hooks, leaving
file inodes and the generation link intact. Summary verbosity and higher print
one reuse message; quiet mode prints none.

Fingerprinting happens at runtime, so secret files specified with absolute
string paths remain supported. Missing or modified plaintext, permissions,
ownership, or custom symlinks trigger installation again. Ciphertext changes,
including re-encryption of the same plaintext, also trigger decryption. Cache
metadata is accessible only to root and is recorded after a successful
installation. Generations retain their numbered names.

The cache reuses the entire generation: a changed input causes all enabled
secrets to be installed again. It cannot detect changes in an external key
provider or a mutable custom age program. Set `age.cacheDecryption = false`
when those dependencies must be checked on every activation, or to force
decryption while debugging. Home Manager does not currently use this cache.

### `age.secrets`

`age.secrets` is an attrset of encrypted secrets. Defaults to `{}`.

### `age.derivedSecrets`

On NixOS and nix-darwin, `age.derivedSecrets` renders configuration files from
public templates and decrypted secrets during activation. Defaults to `{}`.

```nix
{ config, pkgs, ... }: {
  age.secrets.password.file = ./password.age;
  age.derivedSecrets.service-config = {
    template = pkgs.writeText "service-config.template" ''
      password=@password@
    '';
    secrets = [ config.age.secrets.password ];
    owner = "my-service";
    restartUnits = [ "my-service.service" ]; # NixOS only
  };
  # Point the service at config.age.derivedSecrets.service-config.path.
}
```

The `template` option is a required path to a public template. It can be a Nix
store path or an absolute runtime path. Templates must not contain plaintext
secrets: store paths and files created with `pkgs.writeText` are public.

The `secrets` list defaults to `[]` and must reference enabled entries in
`config.age.secrets`. Each input's `@name@` placeholder uses its `name` option,
which defaults to its attribute name. Only listed inputs are replaced; other
text remains unchanged. Substitution happens once, so placeholder text inside a
secret is not expanded again. The default `format = "text"` inserts literal bytes.

`environmentFiles` defaults to `[]` and also references enabled entries in
`config.age.secrets`. These files contain single-line `KEY=value` assignments.
They supply `$KEY` and `${KEY}` placeholders without evaluating shell code or
reading the process environment. Later files override earlier definitions.
An undefined variable or malformed assignment fails rendering.

Set `format = "json"` to escape inserted values as JSON string contents and
validate the complete output. Put placeholders inside JSON quotes. This applies
to both `secrets` and `environmentFiles` substitutions and requires UTF-8 values.
See [Environment templates](#environment-templates) for the supported assignment
syntax and a complete example.

`trimFinalNewline` defaults to `true`, removing at most one final LF or CRLF
from each `secrets` input before substitution. Set it to `false` to preserve every byte.
Inputs without a final newline are unchanged.

Derived secrets support the same `enable`, `name`, `path`, `mode`, `owner`,
`group`, `symlink`, `onChange`, `reloadUnits`, and `restartUnits` options as
encrypted secrets below. They use `template`, `secrets`, and `environmentFiles`
instead of `file`.
Enabled encrypted and derived secrets must have distinct names. A disabled
derived secret does not need a template.

All encrypted inputs are decrypted before templates are rendered. Rendering
uses the new generation's inputs, including inputs installed at custom paths.
Plaintext output is created at activation time, outside the Nix store. A
rendering failure preserves the previous generation and skips change hooks.
Templates cannot depend on other derived secrets. Home Manager does not
currently support this option.

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

### `age.secrets.<name>.onChange`

A shell script to run as root after an update changes this secret's plaintext,
mode, owner, or group, or installs it at a new destination. Defaults to `""`.
Hooks run after all secrets are installed and ownership is assigned, and are
skipped during boot. A re-encryption with unchanged plaintext and permissions
does not run the hook. The new configuration's hook is used.

If installation fails, hooks are skipped. If a hook fails, the error is reported
and the successfully installed secrets remain in place.

### `age.secrets.<name>.reloadUnits` and `restartUnits`

Lists of systemd units to reload or restart when this secret changes. Both
default to `[]` and apply only on Linux. Units that are inactive remain
inactive. A restart takes precedence if a unit is listed in both options.

```nix
age.secrets.service-config = {
  file = ./service-config.age;
  restartUnits = [ "my-service.service" ];
};
```

During a traditional NixOS configuration switch, requests are passed to
`switch-to-configuration`. During service-based installation or manual
activation, requests are queued with systemd after secret installation. Queuing
avoids blocking on a consumer that itself waits for agenix to finish.

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

```
agenix - edit, rekey, and check age secret files

agenix -e FILE [-i PRIVATE_KEY]
agenix -r [-i PRIVATE_KEY]
agenix -c

options:
-h, --help                show help
-e, --edit FILE           edits FILE using $EDITOR
-r, --rekey               re-encrypts all secrets with specified recipients
-c, --check               checks encrypted SSH recipients against the rules
-d, --decrypt FILE        decrypts FILE to STDOUT
-i, --identity            identity to use when decrypting
-v, --verbose             verbose output

FILE an age-encrypted file

PRIVATE_KEY a path to a private SSH key used to decrypt file

EDITOR environment variable of editor to use when editing FILE

If STDIN is not interactive, its contents replace the secret.
Piped input replaces a secret without decrypting it first.

AGENIX_RULES environment variable with path to Nix file specifying recipient public keys.
Searches the current directory for agenix-rules.nix, then secrets.nix.
Searches parent directories for agenix-rules.nix only.
Resolves relative secret paths from the selected rules file's directory.
```

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
