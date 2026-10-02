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

## AI assistance and review {#ai-assistance}

Contributors may use AI tools, but remain responsible for understanding their
changes and explaining how they were checked. Disclose material AI assistance
in the PR description, including which parts of the implementation, tests,
documentation, or review were assisted. Routine editor completion does not
need a separate disclosure.

Describe validation that actually ran, its results, and any remaining limits.
Generated tests and an AI review do not establish correctness on their own.
Never include private keys, decrypted secrets, or other confidential data in
prompts, PR descriptions, logs, or test fixtures.

Every PR needs approval from a human reviewer before merging. Automated
checks and AI reviews can support that review; they do not count as the
required approval. Maintainers decide whether a change is ready to merge or
include in a release. Passing CI or opening a PR does not imply maintainer
endorsement.

Keep each PR focused on a change that a person can reasonably review. Explain
dependencies between stacked PRs and avoid mixing unrelated fixes. If a
reviewer cannot establish that a change is understood or adequately checked,
the change needs more work before approval, regardless of which tools were
used to produce it.


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
