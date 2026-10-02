# Sharing rules through a flake {#flake-rules}

You can define recipient rules in `flake.nix` and expose them to the CLI through
a small `agenix-rules.nix` file. This lets rules, helper functions, and your
NixOS configuration share the same public-key data and flake inputs.

For a Git checkout, add a custom output to your existing `flake.nix`:

```nix
{
  outputs = { self, ... }:
    let
      keys = builtins.fromJSON (builtins.readFile ./keys.json);
    in
    {
      agenixRules = {
        "secrets/service.age".publicKeys = keys.recipients;
      };

      # Other outputs, including nixosConfigurations, can use the same keys.
    };
}
```

Here `keys.json` contains public recipients, for example a `recipients` array
of SSH public-key strings. Keep private identities outside the repository.
Rules may also call helper functions or use explicitly declared flake inputs;
they do not need an `import <nixpkgs>` lookup.

Place this `agenix-rules.nix` beside `flake.nix`:

```nix
(builtins.getFlake ("git+file://" + toString ./.)).agenixRules
```

The explicit Git reference uses the checkout's tracked files and avoids copying
its `.git` metadata. Add `flake.nix`, `agenix-rules.nix`, `keys.json`, any imported
files, and your ciphertext to Git. If the flake has external inputs, create and
commit its `flake.lock` with your normal flake workflow.

Enable the `flakes` experimental feature in Nix. The CLI evaluates local rules
with `--impure`, allowing `getFlake` to read the current checkout. See the
[Nix documentation for `getFlake`](https://nix.dev/manual/nix/stable/language/builtins.html#builtins-getFlake).

Use the ordinary CLI commands from the checkout root or a nested directory:

```ShellSession
$ agenix --edit secrets/service.age
$ agenix --rekey -i ~/.ssh/id_ed25519
```

Secret filenames remain relative to the `agenix-rules.nix` directory. Updating
the public-key data changes the rules used by subsequent commands; rekey the
affected ciphertext after changing recipients. Define `agenixRules` independently
of the small rules file above, since importing it back into that output would
create a recursive evaluation.
