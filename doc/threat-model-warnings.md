# Threat model/Warnings {#threat-model-warnings}

This project has not been audited by a security professional.

People unfamiliar with `age` might be surprised that secrets are not
authenticated. This means that every attacker that has write access to
the secret files can modify secrets because public keys are exposed.
This seems like not a problem on the first glance because changing the
configuration itself could expose secrets easily. However, reviewing
configuration changes is easier than reviewing random secrets (for
example, 4096-bit rsa keys). This would be solved by having a message
authentication code (MAC) like other implementations like GPG or
[sops](https://github.com/Mic92/sops-nix) have, however this was left
out for simplicity in `age`.

Encrypt only secrets that you can rotate if their contents are exposed in the
future. As of June 2024, [age is not post-quantum
safe](https://github.com/FiloSottile/age/discussions/231#discussioncomment-3092773).
Someone who can collect encrypted files today may retain them and decrypt
them if future advances make that possible. See the discussion in
[age issue #578](https://github.com/FiloSottile/age/issues/578).
