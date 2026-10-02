# agenix - [age](https://github.com/FiloSottile/age)-encrypted secrets for NixOS {#introduction}

`agenix` deploys [age](https://github.com/FiloSottile/age)-encrypted secrets
with NixOS, nix-darwin, and Home Manager modules. The modules put encrypted
files in the Nix store and decrypt them on the intended machine or user
account. Applications read the resulting plaintext files at runtime.

The optional `agenix` command-line tool helps you create, edit, and rekey
encrypted files. Its `agenix-rules.nix` file maps filenames to recipient
public keys. The deployment modules do not read that rules file; they use
the encrypted paths declared in `age.secrets` and the private identities in
`age.identityPaths`.

## Editing, building, and deployment {#secret-lifecycle}

| Stage | What it needs |
| --- | --- |
| Create an encrypted secret | Plaintext and the recipients' public keys |
| Edit or rekey an existing secret | A private identity that can decrypt it, plus the desired recipient public keys |
| Build a Nix configuration | The configuration and encrypted files; no private identities or plaintext |
| Activate on the target | The built configuration and a private identity able to decrypt each secret |

The editing machine, build machine, and target can be different machines.
Include the target's public key so it can decrypt the secret. Include an
editor's public key if that person should be able to edit or rekey it later;
an editor identity is not required merely to deploy the file.

You can encrypt files with `age` directly and deploy them with the modules.
The CLI adds recipient rules, editor integration, and rekeying convenience;
it is not a prerequisite for module use. See the [tutorial](#tutorial) for
the directory layout, key types, and activation timing.
