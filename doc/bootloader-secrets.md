# Secrets for bootloader installation {#bootloader-secrets}

NixOS installs bootloader files before activating the new configuration.
Normal `age.secrets` are therefore too late for a new GRUB password hash or
an SSH private key that must be appended to the initrd. The optional
`nixosModules.bootloader` module adds `age.bootloaderSecrets` for these inputs.
It includes the normal agenix module, so importing both is unnecessary.

```nix
{ config, inputs, ... }: {
  imports = [ inputs.agenix.nixosModules.bootloader ];

  # A runtime string, not a Nix path that copies the private key to the store.
  # Provision this identity before the first installation or rebuild.
  age.identityPaths = [ "/persist/agenix/identity.txt" ];

  age.bootloaderSecrets = {
    grub-password.file = ./grub-password.age;
    initrd-ssh.file = ./initrd-ssh.age;
  };

  boot.loader.grub.users.admin.hashedPasswordFile =
    config.age.bootloaderSecrets.grub-password.path;

  boot.initrd.network.enable = true;
  boot.initrd.network.ssh = {
    enable = true;
    hostKeys = [ config.age.bootloaderSecrets.initrd-ssh.path ];
    authorizedKeys = [ "ssh-ed25519 AAAA... administrator" ];
  };
}
```

Configure your bootloader and storage normally in addition to this example.
GRUB's `hashedPasswordFile` expects the PBKDF2 hash produced by
`grub-mkpasswd-pbkdf2`; encrypt that hash with agenix. Use a separate SSH key
for the initrd. Its private key is included in the boot files, which may be on
an unencrypted partition. Do not reuse the identity that decrypts your other
agenix secrets. The bootloader must support appending initrd secrets; copying
private keys into a store-built initrd exposes them through the Nix store.

The wrapper decrypts every enabled bootloader secret before calling the
configured bootloader installer. A decryption failure stops that invocation.
It runs for bootloader updates during `switch`, `boot`, and installation,
including when pre-switch checks are disabled. A `test` activation does not
install the bootloader and does not prepare these secrets. The identity must
already be available at that point: activation scripts, newly generated host
keys, and user services cannot provision it in time. When using `nixos-install`,
provision it at the corresponding path inside the target filesystem first.

The files are root-owned and mode `0400`, under the real directory
`/run/agenix-bootloader` with mode `0700`. Decryption uses a private staging
directory and publishes files only after all inputs decrypt. Files published
by the wrapper and staging files are removed when the installer returns,
including on an error. `/run` is normally tmpfs; account for swap in your
host's secret storage policy. Normal `age.secrets` generations and service
ownership are unaffected. Do not use these temporary paths as inputs to
ordinary running services.

When the initrd copies an SSH key into `/run/agenix-bootloader` at boot, it
creates a real directory. This is compatible with later bootloader updates
and does not conflict with the `/run/agenix` generation symlink. An old
configuration that already left a real `/run/agenix` directory needs manual
migration: inspect its files, move the initrd key to this separate mechanism,
and reboot with the corrected initrd. Do not delete an unfamiliar directory
of secrets as part of a rebuild.

Each `age.bootloaderSecrets.<name>` has `file`, `enable` (default `true`), and
read-only `path` options. A disabled entry needs no `file`. Names must start
with a letter, digit, or underscore and otherwise contain only letters,
digits, underscores, dots, and hyphens. The module uses `age.identityPaths`,
`age.ageBin`, and `age.validateSecrets` from the normal module. It is available
only on NixOS. It wraps `system.build.installBootLoader` through the option's
`apply` function; another module defining an `apply` function for that same
option requires manual integration.
