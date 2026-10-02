# Project rules discovery {#project-rules-discovery}

Put `agenix-rules.nix` at the project root to use parent discovery from deeper
directories. A nearer rules file takes precedence. Rule keys and command-line
secret names are relative to the
selected rules file's directory, even when the shell is in a deeper directory.

For this layout:

```text
project/
  agenix-rules.nix
  secrets/
    alertmanager.age
  hosts/
    web/
```

Use a root rules file with the directory included in the key:

```nix
{
  "secrets/alertmanager.age".publicKeys = [
    "ssh-ed25519 REPLACE_WITH_YOUR_PUBLIC_KEY"
  ];
}
```

Then both commands select the same secret:

```sh
# From project/:
agenix --edit secrets/alertmanager.age
# From project/hosts/web/:
agenix --edit secrets/alertmanager.age
```

If the rules already live in `secrets/agenix-rules.nix` with keys such as
`"alertmanager.age"`, keep them there and add this small root `agenix-rules.nix`:

```nix
let
  rules = import ./secrets/agenix-rules.nix;
in
builtins.listToAttrs (
  map (name: {
    name = "secrets/${name}";
    value = rules.${name};
  }) (builtins.attrNames rules)
)
```

This prefixes the imported keys to match the root directory. A simple `import`
without that prefix would interpret `alertmanager.age` in the root instead.

Alternatively, select the nested file explicitly and use its own relative keys:

```sh
AGENIX_RULES="$(git rev-parse --show-toplevel)/secrets/agenix-rules.nix" \
  agenix --edit alertmanager.age
```

This form uses Git only to construct an absolute path. Agenix itself does not
need Git for discovery, and does not recursively search descendant directories
or choose between multiple nested rule sets. Explicit `AGENIX_RULES` takes
precedence; otherwise a current-directory rules file takes precedence over a
parent's `agenix-rules.nix`.

Automatic discovery of the legacy `secrets.nix` name is limited to the current
directory and is deprecated. Rename it to `agenix-rules.nix` to use parent
discovery, or select it explicitly through `AGENIX_RULES`. Each secret must still
have a matching entry in the selected rules file.
