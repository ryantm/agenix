{ pkgs }:
let
  # Assert the output staging location and simulate a partial encryption failure.
  age = pkgs.writeShellScript "age-encryption-test" ''
    args=("$@")
    decrypt=0
    output=
    while (( $# )); do
      case "$1" in
        --decrypt) decrypt=1; shift ;;
        -o) output=$2; shift 2 ;;
        *) shift ;;
      esac
    done
    if (( ! decrypt )); then
      case "$output" in nested/.agenix.*/secret.age) ;; *) exit 42 ;; esac
      if [[ -v FAIL_ENCRYPTION ]]; then
        printf 'incomplete ciphertext' > "$output"
        exit 43
      fi
    fi
    exec ${pkgs.age}/bin/age "''${args[@]}"
  '';
  cli = (pkgs.callPackage ../pkgs/agenix.nix { ageBin = age; }).overrideAttrs {
    doInstallCheck = false;
  };
in
pkgs.runCommand "agenix-cli-encryption" { nativeBuildInputs = [ cli ]; } ''
  export HOME="$TMPDIR/home"
  export NIX_STORE_DIR="$TMPDIR/store"
  export NIX_STATE_DIR="$TMPDIR/state"
  mkdir -p "$HOME" "$NIX_STORE_DIR" "$NIX_STATE_DIR" work plaintext
  cd work
  cat > agenix-rules.nix <<'EOF'
  { "nested/secret.age".publicKeys = [ "${builtins.readFile ../example_keys/user1.pub}" ]; }
  EOF
  export TMPDIR="$PWD/../plaintext"
  printf original | agenix -e nested/secret.age
  chmod 400 nested/secret.age
  cp nested/secret.age original.age
  if printf replacement | FAIL_ENCRYPTION=1 agenix -e nested/secret.age; then
    echo 'partial encryption unexpectedly succeeded' >&2
    exit 1
  fi
  cmp original.age nested/secret.age
  test -z "$(find nested -name '.agenix.*')"
  test -z "$(ls -A "$TMPDIR")"
  printf replacement | agenix -e nested/secret.age
  test "$(agenix -d nested/secret.age -i ${../example_keys/user1})" = replacement
  test -z "$(find nested -name '.agenix.*')"
  test -z "$(ls -A "$TMPDIR")"
  touch "$out"
''
