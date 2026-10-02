# Rekeying {#rekeying}

If you change the public keys in `agenix-rules.nix`, you should rekey your
secrets:

```ShellSession
$ agenix --rekey
```

To rekey one file after changing its recipient list:

```ShellSession
$ agenix --rekey-file secrets/database.age -i ~/.ssh/id_ed25519
```

The filename is relative to the selected rules file's directory and must match
a rule. Only that rule is evaluated and only that file is re-encrypted. The
command requires an identity that can decrypt the existing file, does not open
an editor, and ignores piped input. Quote filenames containing spaces.

To rekey only secrets whose current rules include a particular public key,
pass the key as a quoted argument:

```ShellSession
$ agenix --rekey 'ssh-ed25519 AAAA... server-name' -i ~/.ssh/id_ed25519
```

The argument must exactly match a public key string in the rules, including
any comment. Selection uses the current rules, so a newly added recipient
selects the secrets that need to be encrypted for it. Other files are left
unchanged. An empty argument or a key absent from all rules is an error.
Omit the public key to rekey all secrets. `-i` still selects the private key
used for decryption.

To rekey a secret, you have to be able to decrypt it. Because of
randomness in `age`'s encryption algorithms, the files always change
when rekeyed, even if the identities do not. (This eventually could be
improved upon by reading the identities from the age file.)
