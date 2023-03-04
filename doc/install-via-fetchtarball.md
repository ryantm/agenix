# Install via fetchTarball {#install-via-fetchtarball}

#### Install module via fetchTarball

Add the following to your configuration.nix:

```nix
{
  imports = [ "${builtins.fetchTarball "https://github.com/ryantm/agenix/archive/main.tar.gz"}/modules/age.nix" ];
}
```

  or with pinning:

```nix
{
  imports = let
    # replace this with an actual commit id or tag
    commit = "298b235f664f925b433614dc33380f0662adfc3f";
  in [
    "${builtins.fetchTarball {
      url = "https://github.com/ryantm/agenix/archive/${commit}.tar.gz";
      # update hash from nix build output
      sha256 = "";
    }}/modules/age.nix"
  ];
}
```

#### Install CLI via fetchTarball

To install the `agenix` binary:

```nix
{
  environment.systemPackages = [ (pkgs.callPackage "${builtins.fetchTarball "https://github.com/ryantm/agenix/archive/main.tar.gz"}/pkgs/agenix.nix" {}) ];
}
```
