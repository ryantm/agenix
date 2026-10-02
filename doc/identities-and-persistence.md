# Identities and persistence {#identities-and-persistence}

The NixOS module normally decrypts with the machine's SSH host identities.
Encrypting a secret to a user's public key does not make the system module search
that user's home directory. Likewise, `owner = "alice"` controls the decrypted
file's ownership, not which key is used to decrypt it.

For a system service, encrypt the file to a host recipient whose private identity
is available during activation. If the file must instead use a user's identity,
configure that path explicitly. For example, on a system with existing persistent
storage:

```nix
{
  age.identityPaths = [
    "/persist/etc/ssh/ssh_host_ed25519_key"
    "/persist/home/alice/.ssh/id_ed25519"
  ];
  fileSystems."/persist".neededForBoot = true;
}
```

Use the actual persistent paths on your machine. This replaces the default
identity list, so include every identity the configuration needs. The filesystem
must already be declared and the keys must already exist; `neededForBoot` does
not create or persist them. Absolute string paths keep private keys out of the
Nix store.

On systems that erase their root filesystem at boot, persist the identities and
make their storage available before agenix runs. Pointing directly to the
persistent copy avoids depending on a later home-directory bind mount. Mounting
`/home` early does not add its keys to `age.identityPaths`. If the home or key is
only unlocked after login, use the Home Manager module for user-session secrets,
or use a different identity for secrets needed during system activation.

The Home Manager module has its own `age.identityPaths`, normally the user's
Ed25519 and RSA SSH key paths. Its options are separate from the system module's
options. The CLI also has separate `-i` settings; these do not change either
module's activation configuration.

## Diagnosing recipient failures

`no identity matched any of the recipients` means the attempted identities could
not decrypt the ciphertext. Check the identity paths on the target machine and
the recipients used when the file was last encrypted. Editing the rules alone
does not change existing ciphertext: rekey after adding a recipient.

To check a specific identity without printing the plaintext:

```sh
sudo age --decrypt -i /persist/etc/ssh/ssh_host_ed25519_key \
  ./secrets/service-token.age >/dev/null
```

If the ciphertext is encrypted only to Alice's key, a host key cannot decrypt it.
Test the identity that actually corresponds to one of its recipients. A successful
interactive test does not supply a passphrase prompt to an unattended service.

## Making encrypted files available on a new machine

Encrypted input files should normally enter the target's store closure through
a Nix path or a string with store context. These forms support constructed names:

```nix
age.secrets.token.file = ./secrets + "/service-token.age";
```

Or, when selecting a file inside a copied directory:

```nix
age.secrets.token.file = "${./secrets}/service-token.age";
```

Choose one form, and track the encrypted inputs when using a Git flake. String
interpolation copies the referenced path into the store. `toString ./secrets`
does not perform that copy; concatenating a filename onto the resulting string
can leave a path that only exists on the machine doing the evaluation. Similarly,
a plain store-path string does not establish a dependency on its producing
derivation. Use `"${package}/path/to/file.age"` for package outputs.

A deliberate runtime string such as `"/var/lib/provisioned/token.age"` requires
that file to be provisioned on the target before activation. A missing ciphertext
warning in that case concerns file availability, independently of whether the
private identity can decrypt it.
