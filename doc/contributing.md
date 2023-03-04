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
```

You can run the integration tests in interactive mode like this:

```ShellSession
nix run .#checks.x86_64-linux.integration.driverInteractive
```

After it starts, enter `run_tests()` to run the tests.
