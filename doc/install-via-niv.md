# Install via [niv](https://github.com/nmattia/niv) {#install-via-niv}

First add it to niv:

```ShellSession
$ niv add ryantm/agenix
```

## Install module via niv

Then add the following to your `configuration.nix` in the `imports` list:

```nix
{
  imports = [ "${(import ./nix/sources.nix).agenix}/modules/age.nix" ];
}
```

## Install CLI via niv

To install the `agenix` binary:

```nix
{
  environment.systemPackages = [ (pkgs.callPackage "${(import ./nix/sources.nix).agenix}/pkgs/agenix.nix" {}) ];
}
```
