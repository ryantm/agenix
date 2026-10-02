# Home Manager application secrets {#home-manager-application-secrets}

For an application that reads a secret file from a fixed location, set the
Home Manager secret's `path` to that location. Agenix decrypts the file when its
user service runs and creates the destination's parent directories.

For example, to provide GitHub CLI's `hosts.yml`:

```nix
{ config, inputs, ... }:
{
  imports = [ inputs.agenix.homeManagerModules.default ];

  programs.gh.enable = true;
  age.identityPaths = [ "${config.home.homeDirectory}/.ssh/id_ed25519" ];
  age.secrets.gh-hosts = {
    file = ./hosts.yml.age;
    path = "${config.xdg.configHome}/gh/hosts.yml";
  };
}
```

Leave [`programs.gh.hosts`](https://github.com/nix-community/home-manager/blob/release-26.05/modules/programs/gh.nix)
at its empty default. That Home Manager option takes
configuration data to serialize into a store file, rather than the path of a
runtime secret. Likewise, do not declare a `home.file` or `xdg.configFile` entry
for the same destination. Agenix manages it directly.

By default the destination is a symlink to the current decrypted generation,
with mode `0400`. GitHub CLI can read this configuration. Operations that rewrite
credentials, such as `gh auth login`, should instead be made in the source
configuration and re-encrypted before switching. If another application requires
a regular file, set `symlink = false`; that creates plaintext at the destination,
which persists outside the runtime directory and must be removed when no longer
needed. Prefer the default symlink where the application supports it.

## Applying changes

On Linux, Home Manager's
[`systemd.user.startServices = true`](https://github.com/nix-community/home-manager/blob/release-26.05/modules/systemd.nix)
uses `sd-switch` to
reload changed units and start the agenix service. This is the default in the
Home Manager release tested by agenix. Changes to `age.identityPaths` or encrypted
files take effect during a normal `home-manager switch` in a running user session.

If `systemd.user.startServices` is `false` or `"suggest"`, Home Manager prints the
service operations to perform manually. For agenix, run:

```sh
systemctl --user daemon-reload
systemctl --user restart agenix.service
```

Do not run these commands with `sudo`: the Home Manager service belongs to your
user. A switch outside a running user manager can build and link configuration
without starting the service; it will run at the next login. On distributions
other than NixOS, Home Manager's `systemd.user.systemctlPath` may need to point to
the host's `systemctl`.

If the destination is missing or its symlink is broken, inspect the service:

```sh
systemctl --user status agenix.service
journalctl --user -u agenix.service -b
systemctl --user show agenix.service -p ExecStart
```

Check that the configured identity exists, is readable and non-empty, and can
decrypt the file. Native age identity files are supported too, but must be listed
in `age.identityPaths`; the default only includes the user's Ed25519 and RSA SSH
key paths. Prepare replacement identities before switching to the configuration
that needs them. A private key obtained from another secret cannot bootstrap its
own decryption.
