# Comparing secrets in Git {#git-diffs}

Git can decrypt age files for a local, readable diff. You need an identity that
can decrypt both revisions. The repository continues to store ciphertext.

Add this entry to `.gitattributes` at the repository root:

```gitattributes
*.age diff=age
```

Install `age` and configure its diff driver in your local checkout:

```ShellSession
$ git config --local diff.age.textconv 'age --decrypt -i "$HOME/.ssh/id_ed25519"'
$ git config --local diff.age.cachetextconv false
```

Use the path to your identity file; a native age identity file also works. Git
passes a temporary ciphertext filename to the command. Direct `age` decryption
works for those historical blobs without needing a matching CLI rules entry.

Compare two commits from a terminal with the pager disabled:

```ShellSession
$ git --no-pager diff --textconv HEAD~1 HEAD -- secrets/database.age
```

For changes in your working tree, omit the two revisions. With an encrypted SSH
identity, age prompts for its passphrase for each version it decrypts. Keeping
the pager disabled lets those prompts use the terminal without competing with
the pager. You may need to enter the passphrase twice for one file.

The diff contains plaintext, so treat terminal output and any redirected output
as secret data. Keep `diff.age.cachetextconv` false: enabling Git's textconv
cache stores decrypted results in Git objects. Disabling it does not erase a
cache that was created earlier. These readable diffs are for review and cannot
be applied as encrypted patches.

See Git's [textconv documentation](https://git-scm.com/docs/gitattributes#_performing_text_diffs_of_binary_files)
for conversion and caching behavior, and [`--no-pager`](https://git-scm.com/docs/git#Documentation/git.txt---no-pager)
for terminal output control.
