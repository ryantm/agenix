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

The Markdown files in `doc/` are the maintained documentation. Linux CI and
the GitHub Pages deployment both render them with `ryantm/mmdoc-action@v1`,
using `doc/` as the source. To render the site locally with the mmdoc version
currently used by the action:

```ShellSession
nix run github:ryantm/mmdoc/0.27.0 -- agenix doc /tmp/agenix-doc
```

The output contains `multi/` for the website, `single/` for a single-page
HTML version, `man/` pages, and an EPUB. The deployment workflow publishes
`multi/` from `main`. The former `packages.<system>.doc` flake output is
retired; use the action or the local command above to build documentation.
Edit `doc/toc.md` when adding or rearranging pages so the site's navigation
stays in sync.

## CLI scope and compatibility plan

Keep `agenix --check` as an SSH recipient drift check that does not require a
private key. Extra recipients are reported by their stanza type and short tag;
scanning Nix source to guess a full public key is no longer part of its scope.
This keeps results independent of whether rules use inline keys, imported
files, or computed expressions. The checker still needs OpenSSH to derive SSH
tags and GNU sed to read headers and armor. This simplification does not remove
those dependencies, add a new interpreter, or introduce package variants.

The rules-discovery migration follows this release plan:

* Retain the `RULES` variable and current-directory `secrets.nix` discovery
  throughout 0.19.x, with warnings. Include the migration and removal version
  in the 0.19.0 release notes.
* In 0.20.0, remove those two deprecated discovery paths and their compatibility
  tests. Announce the removal in the release notes. Keep explicit filenames,
  including `AGENIX_RULES=secrets.nix`.
* If the announcement misses 0.19.0, postpone removal until after a full minor
  release series containing the announcement; update the warning and reference
  documentation together.

Examples and ordinary tests use `agenix-rules.nix` and `AGENIX_RULES`. Dedicated
compatibility tests continue to exercise the deprecated discovery behavior
until its scheduled removal.
