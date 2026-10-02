# Plugins during NixOS installation {#install-plugins}

Include plugin executables in the target configuration so they are part of
its Nix store closure and available during secret decryption:

```nix
{ pkgs, ... }: {
  age.pluginPackages = [ pkgs.age-plugin-yubikey ];
  age.identityPaths = [ "/etc/agenix/yubikey-identity.txt" ];
}
```

Before `nixos-install`, provision that identity at
`/mnt/etc/agenix/yubikey-identity.txt` when the target root is `/mnt`.
Configure the path as seen **inside the installed system**, without `/mnt`.
A YubiKey identity file contains plugin metadata; obtain it using the
[plugin's documented identity export](https://github.com/str4d/age-plugin-yubikey#configuration).
Keep a recovery recipient for secrets needed to bootstrap a machine.

The installer can export a temporary directory such as `/mnt/tmp.example`
before entering the target root. That directory is outside the resulting
chroot, even though the plugin binary itself is present. In particular,
rage allocates a temporary working directory before starting a plugin, so
an inaccessible `TMPDIR` prevents plugin startup.

Agenix supplies a private temporary directory under `age.secretsMountPoint`
for each decryption and removes it on exit, including failure. Age and its
plugins therefore use the target's secrets filesystem without depending on
the installer's inherited `TMPDIR`. The plugin's executable still needs to
be on `PATH`; `age.pluginPackages` handles this separately.

Hardware-backed plugins also need their device or daemon available from
inside the chroot. Enabling a daemon such as `services.pcscd` in the target
configuration prepares it for boot; it does not start that daemon in the
installer's running system. Check the plugin's hardware prerequisites in
the installer and the visibility of any daemon socket inside the target.
The temporary-directory fix does not arrange hardware access or supply a
PIN/password agent.

The regression test uses `nixos-install`, `nixos-enter`, rage, and a real
age-protocol fixture plugin with public test keys. It covers chroot path
handling and cleanup; physical YubiKey operation needs separate hardware
validation.
