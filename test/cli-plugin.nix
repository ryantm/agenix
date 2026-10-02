{ pkgs }:
let
  # Test the CLI/age argument contract without requiring plugin hardware.
  ageStub = pkgs.writeShellScript "age-plugin-test" ''
    args=()
    while (( $# )); do
      case "$1" in
        -j)
          test "$2" = fixture || exit 42
          args+=(--identity ${../example_keys/user1})
          shift 2
          ;;
        --identity)
          echo 'unexpected file identity with -j' >&2
          exit 43
          ;;
        *) args+=("$1"); shift ;;
      esac
    done
    exec ${pkgs.age}/bin/age "''${args[@]}"
  '';
  cli =
    (pkgs.callPackage ../pkgs/agenix.nix {
      ageBin = ageStub;
    }).overrideAttrs
      { doInstallCheck = false; };
in
pkgs.runCommand "agenix-cli-plugin" { nativeBuildInputs = [ cli ]; } ''
  export HOME="$TMPDIR/home"
  export NIX_STORE_DIR="$TMPDIR/store"
  export NIX_STATE_DIR="$TMPDIR/state"
  mkdir -p "$HOME" "$NIX_STORE_DIR" "$NIX_STATE_DIR"
  cp -r ${../example} secrets
  chmod -R u+w secrets
  cd secrets
  test "$(agenix -d secret1.age -j fixture)" = hello
  mkdir -p "$HOME/.ssh"
  printf bogus > "$HOME/.ssh/id_ed25519"
  test "$(agenix -d secret1.age -j fixture)" = hello
  EDITOR=: agenix -e secret1.age -j fixture
  agenix -r -j fixture
  test "$(agenix -d secret1.age -j fixture)" = hello
  if agenix -d secret1.age -j unknown; then exit 1; fi
  for args in '-j' '-j -r'; do
    if agenix $args > error 2>&1; then exit 1; fi
    grep -q 'no PLUGIN specified' error
  done
  if agenix -j "" > error 2>&1; then exit 1; fi
  grep -q 'no PLUGIN specified' error
  touch "$out"
''
