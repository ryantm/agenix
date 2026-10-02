# Rekeying {#rekeying}

If you change the public keys in `agenix-rules.nix`, you should rekey your
secrets:

```ShellSession
$ agenix --rekey
```

To rekey only secrets whose current rules include a particular public key,
pass each key as a separate quoted argument:

```ShellSession
$ agenix --rekey 'ssh-ed25519 AAAA... server-name' -i ~/.ssh/id_ed25519
$ agenix --rekey 'ssh-ed25519 AAAA... first-server' 'ssh-ed25519 AAAA... second-server' -i ~/.ssh/id_ed25519
```

Each argument matches an exact public key string in the rules, including
any comment. A match for any selected recipient includes the secret once.
Selection uses the current rules, so a newly added recipient
selects the secrets that need to be encrypted for it. Other files are left
unchanged. An empty argument or no matches across all selected keys is an error.
Omit the public key to rekey all secrets. `-i` still selects the private key
used for decryption.

To rekey a secret, you have to be able to decrypt it. Because of
randomness in `age`'s encryption algorithms, the files always change
when rekeyed, even if the identities do not. (This eventually could be
improved upon by reading the identities from the age file.)
