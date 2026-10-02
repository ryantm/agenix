{ pkgs }:
let
  cli = pkgs.callPackage ../pkgs/agenix.nix { };
in
pkgs.runCommand "agenix-cli-terminal" { nativeBuildInputs = [ pkgs.python3 ]; } ''
  export HOME="$TMPDIR/home"
  export NIX_STORE_DIR="$TMPDIR/store"
  export NIX_STATE_DIR="$TMPDIR/state"
  mkdir -p "$HOME" "$NIX_STORE_DIR" "$NIX_STATE_DIR" plaintext
  ${pkgs.openssh}/bin/ssh-keygen -q -t ed25519 -N fixture-passphrase -f identity
  ${pkgs.jq}/bin/jq -Rn '{"secret.age": {publicKeys: [inputs]}}' < identity.pub > rules.json
  printf '%s\n' 'builtins.fromJSON (builtins.readFile ./rules.json)' > agenix-rules.nix
  printf terminal-fixture | ${pkgs.age}/bin/age -R identity.pub > secret.age
  export TMPDIR="$PWD/plaintext"
  python3 ${./cli-terminal.py} ${cli}/bin/agenix "$PWD/identity"
  test -z "$(ls -A "$TMPDIR")"
  touch "$out"
''
