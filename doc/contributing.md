# Contributing {#contributing}

* The main branch is protected against direct pushes
* All changes must go through GitHub PR review and get at least one approval
* PR titles and commit messages should be prefixed with at least one of these categories:
  * contrib - things that make the project development better
  * doc - documentation
  * feature - new features
  * fix - bug fixes
* Please update or make integration tests for new features
* Use `nix fmt` to format nix code


## Tests

You can run the tests with

```ShellSession
nix flake check
nix flake check ./test --impure
```

The root flake contains the public packages and modules. The test flake has
Home Manager and nix-darwin as inputs. Its nixpkgs input follows the root
flake's nixpkgs input. After updating the root nixpkgs pin, run
`nix flake update agenix/nixpkgs --flake ./test` and commit both lock files.
CI checks that the two lock files resolve nixpkgs to the same revision.
The integration `checks`, `darwinConfigurations`, and Home Manager test
configuration previously exported by the root flake are now under `./test#`.
The test commands use `--impure` because the test flake reads the local root
source through `path:..`.

You can run the integration tests in interactive mode like this:

```ShellSession
nix run --impure ./test#checks.x86_64-linux.integration.driverInteractive
```

After it starts, enter `run_tests()` to run the tests.
