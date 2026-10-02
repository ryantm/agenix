# NixOS user passwords {#nixos-user-passwords}

Use [`users.users.<name>.hashedPasswordFile`](https://github.com/NixOS/nixpkgs/blob/nixos-26.05/nixos/modules/config/users-groups.nix)
with a file containing a password hash.
The encrypted plaintext must be exactly one line containing the salted hash, not
the login password itself and not a Nix expression.

Generate a hash interactively, then paste the resulting line into the agenix
editor for `alice-password.age`:

```sh
nix shell nixpkgs#mkpasswd -c mkpasswd --method=yescrypt
agenix --edit alice-password.age
```

Declare that encrypted file in the CLI's `agenix-rules.nix` with the machine's
public recipient before editing it. The machine must have a matching identity
available during system activation.

In the NixOS configuration:

```nix
{ config, ... }:
{
  age.secrets.alice-password.file = ./secrets/alice-password.age;

  users.mutableUsers = false;
  users.users.alice = {
    isNormalUser = true;
    hashedPasswordFile = config.age.secrets.alice-password.path;
  };
}
```

Keep the secret's default root ownership and `0400` mode. The system's user
management reads the hash; the login user does not need access to that file.
Agenix prepares it before user creation, so it also works when the account does
not exist yet. The NixOS integration tests cover password authentication, and the
userborn test verifies that user creation reads the decrypted hash.

`users.mutableUsers = false` makes configuration authoritative for passwords on
activation. With mutable users, existing account passwords can retain changes
made through user-management tools. Avoid setting multiple password options for
the same account. The older `passwordFile` option is a deprecated alias for
`hashedPasswordFile`; it also expects a hash.

If decryption succeeds but login fails, verify that the username being used is
the one declared in `users.users`, and that the decrypted file contains the hash
of the intended password. A secret named `alice-password` does not choose the
account it applies to; `users.users.alice.hashedPasswordFile` does. Also check
whether the selected login method permits password authentication.

Do not import decrypted Nix code to set `hashedPassword`, or read the decrypted
file during evaluation. That requires an earlier activation and can embed the
hash in a world-readable store result. `hashedPasswordFile` reads the runtime
file during activation and avoids that dependency.
