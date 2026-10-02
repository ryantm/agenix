# NixOS containers {#nixos-containers}

The host can decrypt a secret and expose it to a NixOS container without giving
the container a decryption identity. Use a dedicated directory outside the agenix
generation tree, install regular files there, and bind-mount that directory:

```nix
{
  age.secrets.demo-token = {
    file = ./demo-token.age;
    path = "/run/agenix-containers/demo/token";
    symlink = false;
  };

  systemd.tmpfiles.rules = [
    "d /run/agenix-containers/demo 0700 root root -"
  ];

  containers.demo = {
    autoStart = true;
    bindMounts."/run/secrets" = {
      hostPath = "/run/agenix-containers/demo";
      isReadOnly = true;
    };
    config = {
      system.stateVersion = "26.05";
      # Configure the application to read /run/secrets/token.
    };
  };
}
```

Encrypt the file to the host's recipient. No agenix module or SSH service is
needed inside the container. The example gives container root access; for a
non-root application, set matching numeric ownership/group permissions on the
host file and its parent directory. Containers using user-ID remapping need
ownership that matches their host-side mapped IDs.

Mount the dedicated parent directory, not the individual secret file. A file
bind mount holds onto the old file when agenix replaces it. Similarly, mounting
`/run/agenix` follows the current generation symlink when the container starts
and can pin that generation after it is removed. The dedicated directory remains
in place, so new opens of `/run/secrets/token` see subsequent replacements.

Keep each container's directory limited to secrets it should receive. Mounting
all of agenix's secrets exposes unrelated files to container root. The read-only
mount prevents the container from modifying these host files.

An application that keeps an open file descriptor or caches a credential must
reopen the file, reload, or restart to use an updated value. The mount alone does
not trigger that action. The encrypted configuration remains in the store while
the direct plaintext destination remains under `/run`. Agenix does not remove
custom direct destinations when their declarations are removed; stop the
container and remove obsolete files, or let them disappear at reboot.
