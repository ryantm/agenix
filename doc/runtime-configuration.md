# Runtime configuration {#runtime-configuration}

`config.age.secrets.<name>.path` names a file created during activation. It does
not contain the decrypted value during Nix evaluation. Reading it with
`builtins.readFile` or `lib.fileContents` cannot supply a secret to an option that
expects a string. A successful evaluation-time read would also risk placing that
plaintext in generated store files.

Use the application's file option when it has one. Otherwise, read the secret in
a startup script or provide a runtime configuration file. NixOS options containing
argument lists generally quote their arguments; adding `$(cat ...)` to such a
list does not turn it into a shell command.

## Folding@home

The Folding@home client accepts a configuration file containing the passkey and
account token. Encrypt the complete XML file, for example:

```xml
<config>
  <passkey v="YOUR_PASSKEY"/>
  <account-token v="YOUR_ACCOUNT_TOKEN"/>
</config>
```

Use actual values with XML escaping where required, and encrypt the result as
`fah-config.xml.age`. The client documents account-token configuration in its
[headless setup guide](https://foldingathome.org/guides/v8-4).

The NixOS service uses a dynamic user. A [systemd credential](https://systemd.io/CREDENTIALS/)
lets it read the
configuration while the original agenix secret remains root-owned with mode
`0400`. Wrap the client to pass the credential path at runtime:

```nix
{ config, lib, pkgs, ... }:
{
  age.secrets.fah-config.file = ./fah-config.xml.age;

  services.foldingathome = {
    enable = true;
    user = "YOUR_FOLDING_USERNAME";
    team = 1;
    package = pkgs.writeShellScriptBin "fah-client" ''
      exec ${lib.getExe pkgs.fahclient} \
        --config "$CREDENTIALS_DIRECTORY/config.xml" "$@"
    '';
    extraArgs = [ "--cause=alzheimers" "--beta=false" ];
  };

  systemd.services.foldingathome.serviceConfig.LoadCredential = [
    "config.xml:${config.age.secrets.fah-config.path}"
  ];
}
```

The existing NixOS service still supplies the public user/team flags and applies
its normal service settings. The wrapper only adds the runtime configuration
path. It passes the filename, rather than the secret values, through the process
arguments. This recipe is tested with the pinned NixOS Folding@home module and
client 8.5.3, including the client's FHS wrapper and dynamic user.

Systemd copies the credential when the service starts. Restart the service after
changing the secret to refresh that copy. Folding@home also keeps application
state: its saved settings can override bootstrap values on later starts, so use
the client's configuration interface for those settings. An account token enrolls
a machine; it is not an instruction to reconnect the account on every activation.

For other services, use the same `LoadCredential` pattern with the application's
own file option and read `$CREDENTIALS_DIRECTORY/<name>` in its startup script.
If an application accepts secrets only as command-line values, a runtime wrapper
can read the file, but those values may then be visible in process arguments.
Prefer file-based configuration when supported.
