# Using identities backed by an SSH agent {#ssh-agent}

Setting `SSH_AUTH_SOCK` does not let age decrypt existing `ssh-ed25519` or
`ssh-rsa` recipients. The standard SSH-agent signing operation does not
provide the private-key operations those age recipients need. `IdentityAgent`
in SSH configuration is read by SSH; agenix and age do not use that setting.
See the [age manual](https://github.com/FiloSottile/age/blob/main/doc/age.1.ronn)
and [upstream discussion](https://github.com/FiloSottile/age/discussions/244).

An optional third-party plugin,
[age-plugin-sshagent](https://github.com/eszio/age-plugin-sshagent), derives a
**different age identity** from a deterministic Ed25519 signature. This works
through a stock SSH agent, but changes the security properties: one allowed
signature request can reveal the derived decryption key permanently, even
after agent access is revoked. Read the plugin's security model before using
it, and do not forward an agent holding these keys to untrusted hosts. This
experimental integration is not enabled by default or a cryptographic audit
of the plugin.

The [example package](https://github.com/ryantm/agenix/blob/main/example/ssh-agent-plugin.nix)
pins the plugin source and dependencies. Copy it into your configuration and
add it to the shell where you run agenix:

```nix
pkgs.mkShell {
  packages = [
    inputs.agenix.packages.${pkgs.stdenv.hostPlatform.system}.default
    (pkgs.callPackage ./ssh-agent-plugin.nix { })
  ];
}
```

Start/unlock your agent and load an Ed25519 key using its usual tools. When
a password manager provides the agent, export its documented socket path
as `SSH_AUTH_SOCK` in this shell. The plugin uses that variable; it does not
infer the path from `~/.ssh/config`. Then create the plugin metadata:

```sh
age-plugin-sshagent list
age-plugin-sshagent keygen -o agent-identity.txt
age-plugin-sshagent recipient -i agent-identity.txt
```

For multiple keys, select one with `keygen -k SELECTOR`; consult the plugin's
help for selection rules. Keep `agent-identity.txt` backed up with your key
recovery information. It contains public metadata, including a random salt;
running keygen again creates a new identity.

Put the returned `age1...` recipient in `agenix-rules.nix`:

```nix
{
  "token.age".publicKeys = [ "age1REPLACE_WITH_PLUGIN_RECIPIENT" ];
}
```

The existing agenix identity option selects the plugin metadata for editing,
decryption, and rekeying:

```sh
agenix -e token.age -i ./agent-identity.txt
agenix -d token.age -i ./agent-identity.txt
agenix -r -i ./agent-identity.txt
```

Keep the plugin on `PATH` and the matching key available in the agent. The
metadata is required, so a data-less `-j sshagent` is insufficient.

To migrate existing ciphertext, add the new recipient to its rules and rekey
using an identity that can already decrypt it, for example
`agenix --rekey-file token.age -i /path/to/old-identity`. Verify decryption
with the new metadata before retiring an old recipient. Keep recovery
recipients according to your backup policy.

The integration test uses a real OpenSSH agent after removing the loaded
key's file. It checks decrypt/rekey, migration, missing-key failure without
replacing ciphertext, and a missing socket. Password-manager agents need
their own compatibility and permission checks. This shell workflow does not
provide an agent to NixOS boot services; those still need an independently
available identity.
