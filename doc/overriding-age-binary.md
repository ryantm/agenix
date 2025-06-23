# Overriding age binary {#overriding-age-binary}

The agenix CLI uses `age` by default as its age implemenation, you
can use the `rage` implementation with Flakes like this:

```nix
{
  pkgs,
  lib,
  agenix,
  ...
}:
{
  environment.systemPackages = [
    (agenix.packages.x86_64-linux.default.override { ageBin = lib.getExe pkgs.rage; })
  ];
}
```

Please note that the behavior of alternative implementations may not match that required for agenix to function, and the agenix team does not plan to provide support for bugs encountered when using agenix with nondefault implementations.
