# Overriding age binary {#overriding-age-binary}

The agenix CLI uses `rage` by default as its age implemenation, you
can use the reference implementation `age` with Flakes like this:

```nix
{pkgs,agenix,...}:{
  environment.systemPackages = [
    (agenix.packages.x86_64-linux.default.override { ageBin = "${pkgs.age}/bin/age"; })
  ];
}
```
