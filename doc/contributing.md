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
nix flake check ./test
```

The root flake contains the public packages and modules. The test flake has
Home Manager and nix-darwin as inputs. Its nixpkgs input uses the same
revision as the root flake. After updating the root nixpkgs pin, run
`nix flake update nixpkgs --flake ./test` and commit both lock files. CI
checks that the two lock files resolve nixpkgs to the same revision.
The integration `checks`, `darwinConfigurations`, and Home Manager test
configuration previously exported by the root flake are now under `./test#`.

Run the CLI tests without a VM (they also run during the package install check):

```ShellSession
nix build .#checks.x86_64-linux.cli
```

The NixOS integration check covers activation order, secret ownership, and user services. Run it in interactive mode with:

```ShellSession
nix run ./test#checks.x86_64-linux.integration.driverInteractive
```

After it starts, enter `run_tests()` to run the tests.

## Documentation build

The Markdown files in `doc/` are the maintained documentation. The root
flake's `doc` package renders them with the pinned nixpkgs `mmdoc`:

```ShellSession
nix build .#doc
```

The result contains `multi/` for the website, `single/` for a single-page
HTML version, `man/` pages, and an EPUB. CI builds this package on Linux. The
documentation deployment workflow builds the same package from `main` and
publishes its `multi/` directory to GitHub Pages. Edit `doc/toc.md` when
adding or rearranging pages so the site's navigation stays in sync.
