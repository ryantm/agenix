# NixOS without activation scripts {#native-init}

NixOS is tracking the replacement of activation scripts with services and
other mechanisms in [nixpkgs#475305](https://github.com/NixOS/nixpkgs/issues/475305).
Agenix can already decrypt through systemd services when using Userborn or
systemd-sysusers. This also works with `system.nixos-init.enable`, whose boot
path does not run activation scripts. The integration test boots and reboots
this configuration with Userborn and checks both password-file delivery and
secret ownership.

For example, the following settings select native initialization on the
NixOS version pinned by this repository:

```nix
{
  boot.initrd.systemd.enable = true;
  system.etc.overlay.enable = true;
  services.userborn.enable = true;
  system.nixos-init.enable = true;
}
```

These options affect the whole system. Check the NixOS requirements and the
other modules in your configuration before enabling them. In particular,
`boot.postBootCommands` must be empty for native initialization.

With Userborn or systemd-sysusers, the default
`age.installationMode = "activation"` decrypts in
`agenix-install-secrets.service` **before** users are created, despite the
mode's historical name. `agenix-chown.service` then assigns ownership after
user creation. This mode supports encrypted `users.users.<name>.hashedPasswordFile`.
Its identities must be available during early boot, without depending on
ordinary user services.

For secrets whose identities depend on later services or mounts, use
`age.installationMode = "systemd"`. The install service then decrypts and
assigns ownership after user creation. It cannot supply password hashes for
creating those users; agenix rejects that configuration. Declare any extra
identity-provider dependencies on `systemd.services.agenix-install-secrets`
using `requires` and `after`.

A service that reads a secret should require and follow the relevant agenix
units. In the early Userborn/sysusers mode, wait for ownership as well:

```nix
{
  systemd.services.my-service = {
    requires = [ "agenix-install-secrets.service" "agenix-chown.service" ];
    after = [ "agenix-install-secrets.service" "agenix-chown.service" ];
  };
}
```

For the later `"systemd"` mode, depend only on
`agenix-install-secrets.service`; it performs the ownership step itself.
Replace custom activation-script dependencies with service dependencies when
moving your own consumers to native initialization.

Systemd services are not started by a plain installation chroot. Provision
identities in the target filesystem for the first real boot, and do not
assume that running `nixos-install` has already decrypted these runtime
secrets. Bootloader inputs have an earlier, separate deadline: normal agenix
services cannot provide an initrd key or GRUB password before bootloader
installation. Changing the initialization mode does not change that order.
