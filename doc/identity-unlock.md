# Unlocking an identity at boot {#identity-unlock}

The optional NixOS `nixosModules.identityUnlock` module asks for a passphrase
through systemd password agents, then makes an unlocked identity available to
agenix. The passphrase does not need to reach age through an attached terminal.
This supports a boot-time prompt and rebuilds launched through
`systemd-run --pipe`, including the current nixos-rebuild-ng workflow.

```nix
{ inputs, ... }: {
  imports = [ inputs.agenix.nixosModules.identityUnlock ];

  age.identityUnlock = {
    enable = true;
    format = "ssh";
    file = "/persist/keys/id_ed25519";
  };
  age.secrets.api-token.file = ./api-token.age;
}
```

The module includes the ordinary agenix module. `file` must be available and
readable by root before the unlock service runs. A runtime string as above
keeps the source key out of the Nix store. An encrypted file can also be
referenced as a Nix path; never put an unencrypted private key in the store.
The original file is not modified.

For `format = "ssh"` (the default), supply a passphrase-protected OpenSSH
private key supported by age, such as Ed25519 or RSA. The service copies it
into a private staging directory and uses OpenSSH's askpass mechanism to
remove its passphrase from that copy. It does not pass the password through
command arguments or environment variables.

For a native age identity, first create it and encrypt it with a passphrase
using the age CLI in a private working directory:

```sh
umask 077
age-keygen -o identity.txt
age -p -o identity.txt.age identity.txt
```

Configure `format = "age"; file = ./identity.txt.age;` and encrypt your secret
files to the public recipient printed by `age-keygen`. Retain or remove the
original plaintext identity according to your backup policy; it is not
needed on the target machine. This format uses age's batchpass plugin, with
the password delivered through a pipe opened inside the plugin process. The
pinned age package provides that plugin. The decrypted identity file must
contain native age identities.

Systemd's console or graphical password agent presents the request during
boot. On a running machine, an agent can answer a pending request from a
second terminal:

```sh
sudo systemd-tty-ask-password-agent --query
```

For example, keep this second terminal available when the first terminal is
running `nixos-rebuild switch`. Remote rebuilds need an agent on the target;
a terminal allocated over SSH can run the same command. Without an answering
agent, the request times out. No automatic password cache is enabled. Once
unlocked, the identity remains available for the lifetime of the service, so
ordinary rebuilds do not repeatedly ask for its passphrase.

The module defaults `age.installationMode` to `"systemd"`, so normal secrets
are decrypted after users exist. Consumers must require and follow
`agenix-install-secrets.service`. If you need encrypted user password hashes,
use Userborn or systemd-sysusers and explicitly select
`age.installationMode = "activation"`; agenix then uses its early systemd
services. Traditional activation snippets cannot wait for this service.
Early unlocking requires `format = "age"`; OpenSSH's `ssh-keygen` needs a
root user record that may not exist before Userborn/sysusers runs.
The source identity must be available early in either case; a login-mounted
encrypted home directory cannot provide a key needed to unlock boot.

`age.identityUnlock.path` is a read-only path to the unlocked key. The module
adds it before any other explicitly configured `age.identityPaths`. The key
is root-owned, mode `0400`, inside a mode `0700` ramfs mounted at
`/run/agenix-unlocked-identity`. It is removed and the ramfs is unmounted when
`agenix-unlock-identity.service` stops or fails. Cancelling or entering the
wrong passphrase fails the unlock; restart the unit to retry. Its `prompt`
option changes the displayed message, and `timeout` sets the response timeout
in seconds (default `120`).

A change to a store-backed encrypted identity changes the service command and
causes a rebuild to restart it. After replacing a runtime source file,
restart `agenix-unlock-identity.service` and, if necessary,
`agenix-install-secrets.service`. Stopping the unlock service removes the
identity, but does not revoke secrets that were already decrypted or copied
by applications. This module runs in stage 2; it does not unlock a disk in
the initrd or provide inputs before bootloader installation.

See [systemd password agents](https://systemd.io/PASSWORD_AGENTS/) for the
request mechanism and available user interfaces.
