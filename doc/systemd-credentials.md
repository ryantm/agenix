# Encrypted systemd credentials {#systemd-credentials}

The optional `nixosModules.systemdCredentials` module converts age-encrypted
inputs to encrypted systemd credentials on the target host. Age plaintext
flows directly through a pipe into `systemd-creds`; the shared output files
contain only encrypted data. Systemd decrypts a credential for its consuming
service when that service starts and controls access to the resulting file.
This works with `DynamicUser` without assigning an agenix plaintext file to a
particular account.

```nix
{ inputs, ... }: {
  imports = [ inputs.agenix.nixosModules.systemdCredentials ];

  age.identityPaths = [ "/var/lib/agenix/identity.txt" ];
  age.systemdCredentials.token = {
    file = ./token.age;
    services = [ "my-service" ];
  };

  systemd.services.my-service = {
    wantedBy = [ "multi-user.target" ];
    serviceConfig = {
      Type = "oneshot";
      DynamicUser = true;
      PrivateMounts = true;
    };
    script = ''
      # Pass this filename to your application, or have it read the file.
      test -s "$CREDENTIALS_DIRECTORY/token"
    '';
  };
}
```

The module includes the ordinary agenix module. Normal `age.secrets` can
coexist with these credentials and retain their existing behavior. Continue
using normal secrets for account password hashes or other consumers that run
before ordinary system services. The credential module is NixOS-only and does
not alter nix-darwin or Home Manager.

`agenix-encrypt-credentials.service` runs after local filesystems and prepares
all enabled credentials in a private directory. It publishes a new encrypted
generation only after every decryption and encryption succeeds. A failure
removes the incomplete generation and preserves the previous encrypted files.
No identities or decrypted contents are needed while building the system.
The module uses `age.identityPaths`, `age.ageBin`, and `age.validateSecrets`.
Add any identity-provider dependencies or plugin packages to the preparation
service's `requires`, `after`, and `path` options as needed.

The `services` option accepts NixOS service names without the `.service`
suffix. For each listed consumer, the module adds `LoadCredentialEncrypted`,
`Requires`, and `After`, plus a restart trigger for changes to credential
configuration. An explicit stop or restart of the preparation service
propagates to these consumers. If preparation fails, consumers cannot start;
after repairing the input, restart the preparation service and any consumers
left inactive. A runtime ciphertext change is not a Nix configuration change:
restart the preparation service to convert it. Systemd's credential contents
are fixed for each service invocation.

Each `age.systemdCredentials.<name>` provides:

* `file`: the age-encrypted input.
* `enable`: defaults to `true`; a disabled entry needs no `file`.
* `services`: consumers configured automatically, default `[]`.
* `withKey`: `"auto"` (default), `"host"`, `"tpm2"`, or `"host+tpm2"`, passed
  to `systemd-creds encrypt`. Explicit TPM modes require a working TPM.
* `path`: read-only path to the **encrypted** systemd credential. Use this with
  a manually configured `LoadCredentialEncrypted`, never as a plaintext path.

Names must start with a letter, digit, or underscore, contain only letters,
digits, underscores, dots, and hyphens, and be at most 255 bytes. The encrypted
credential authenticates its name, so use the same name in
`LoadCredentialEncrypted`. Its plaintext is available to the application at
`$CREDENTIALS_DIRECTORY/<name>`.

`"auto"` lets systemd select available host/TPM protection. `"host"` uses
`/var/lib/systemd/credential.secret`; access to that key permits decryption.
TPM modes use systemd's PCR policy defaults. The encrypted files under
`/run/agenix-credentials` are regenerated after boot; do not treat them as
portable backups or commit them instead of the original age files. Provision
the age identity persistently so the host can recreate them.

This service prepares credentials for the running system. It does not embed
them into an initrd or provision a bootloader, and it is not started by a
plain installation chroot. For more about credential lifetime, TPM binding,
and service isolation, see the
[systemd credential documentation](https://systemd.io/CREDENTIALS/).
