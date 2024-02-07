# Overriding age binary {#overriding-age-binary}

The agenix CLI uses `age` by default as its age implemenation, you
can use the `rage` implementation with Flakes like this:

```nix
{pkgs,agenix,...}:{
  environment.systemPackages = [
    (agenix.packages.x86_64-linux.default.override { ageBin = "${pkgs.rage}/bin/rage"; })
  ];
}
```
