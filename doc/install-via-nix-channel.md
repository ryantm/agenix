# Install via nix-channel {#install-via-nix-channel}

As root run:

```ShellSession
$ sudo nix-channel --add https://github.com/ryantm/agenix/archive/main.tar.gz agenix
$ sudo nix-channel --update
```

## Install module via nix-channel

Then add the following to your `configuration.nix` in the `imports` list:

```nix
{
  imports = [ <agenix/modules/age.nix> ];
}
```

## Install Home Manager module via nix-channel

Add the following to your Home Manager configuration:

```nix
{
  imports = [ <agenix/modules/age-home.nix> ];
}
```

## Install CLI via nix-channel

To install the `agenix` binary:

```nix
{
  environment.systemPackages = [ (pkgs.callPackage <agenix/pkgs/agenix.nix> {}) ];
}
```
