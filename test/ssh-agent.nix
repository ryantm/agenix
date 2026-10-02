{ pkgs }:
let
  plugin = pkgs.callPackage ../example/ssh-agent-plugin.nix { };
  agenix = pkgs.callPackage ../pkgs/agenix.nix { };
in
pkgs.runCommand "agenix-ssh-agent-plugin"
  {
    nativeBuildInputs = [
      agenix
      plugin
      pkgs.age
      pkgs.openssh
    ];
  }
  ''
    export NIX_STORE_DIR="$TMPDIR/nix/store"
    export NIX_STATE_DIR="$TMPDIR/nix/var"
    mkdir -p "$NIX_STORE_DIR" "$NIX_STATE_DIR"
    export SSH_AUTH_SOCK="$TMPDIR/agent.sock"
    ssh-agent -D -a "$SSH_AUTH_SOCK" &
    agent_pid=$!
    trap 'kill "$agent_pid"; wait "$agent_pid" || true' EXIT
    for attempt in $(seq 1 100); do
      if test -S "$SSH_AUTH_SOCK"; then break; fi
      sleep 0.01
    done
    ssh-keygen -q -t ed25519 -N "" -f key
    ssh-add key
    # The loaded agent key has no private-key file after this point.
    rm key key.pub
    age-plugin-sshagent keygen -o identity.txt
    recipient=$(age-plugin-sshagent recipient -i identity.txt)
    printf '{ "secret.age".publicKeys = [ "%s" ]; }\n' "$recipient" > agenix-rules.nix
    printf 'agent fixture\n' > expected
    agenix -e secret.age < expected
    agenix -d secret.age -i identity.txt > decrypted
    cmp expected decrypted

    # Standard SSH ciphertext needs its original identity for migration.
    age -R ${../example_keys/user1.pub} -o legacy.age expected
    printf '{ "secret.age".publicKeys = [ "%s" ]; "legacy.age".publicKeys = [ "%s" ]; }\n' \
      "$recipient" "$recipient" > agenix-rules.nix
    if agenix -d legacy.age -i identity.txt > legacy-failed 2>legacy-error; then exit 1; fi
    test ! -s legacy-failed
    grep -q 'no identity matched' legacy-error
    agenix --rekey-file legacy.age -i ${../example_keys/user1}
    agenix -d legacy.age -i identity.txt > migrated
    cmp expected migrated

    agenix -r -i identity.txt
    agenix -d secret.age -i identity.txt > rekeyed
    cmp expected rekeyed
    cp secret.age before.age
    ssh-add -D
    if agenix --rekey-file secret.age -i identity.txt; then exit 1; fi
    cmp before.age secret.age
    if SSH_AUTH_SOCK="$TMPDIR/missing.sock" agenix -d secret.age -i identity.txt > failed; then
      exit 1
    fi
    test ! -s failed
    touch "$out"
  ''
