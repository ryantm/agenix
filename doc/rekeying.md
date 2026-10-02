# Rekeying {#rekeying}

If you change the public keys in `agenix-rules.nix`, you should rekey your
secrets:

```ShellSession
$ agenix --rekey
```

To rekey a secret, you have to be able to decrypt it. Because of
randomness in `age`'s encryption algorithms, the files always change
when rekeyed, even if the identities do not. (This eventually could be
improved upon by reading the identities from the age file.)
