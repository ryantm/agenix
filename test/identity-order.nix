{ pkgs }:
let
  inherit (pkgs) lib;
  identities = pkgs.runCommand "agenix-ordered-public-identities" { } ''
    mkdir "$out"
    cp ${../example_keys/system1} "$out/first identity"
    cp ${../example_keys/user1} "$out/second identity"
  '';
  recordingAge = pkgs.writeShellScript "recording-age" ''
    set -euo pipefail
    args=("$@")
    printf 'call\n' >> "$CALL_LOG"
    first=
    output=
    while test "$#" -gt 0; do
      case "$1" in
        -i) printf '%s\n' "$2" >> "$CALL_LOG"; first="$2"; shift 2 ;;
        -o) output="$2"; shift 2 ;;
        *) shift ;;
      esac
    done
    if test "''${FAIL_FIRST:-0}" = 1 && test "$first" = ${lib.escapeShellArg "${identities}/first identity"}; then
      printf partial > "$output"
      exit 23
    fi
    exec ${pkgs.age}/bin/age "''${args[@]}"
  '';
  script =
    strategy: paths:
    let
      installer = (import ../modules/secret-install.nix { inherit lib; }).installer {
        cfg = {
          verbosity = "quiet";
          identityStrategy = strategy;
          identityPaths = paths;
          secretsDir = "$XDG_RUNTIME_DIR/current";
          secretsMountPoint = "$XDG_RUNTIME_DIR/generations";
          secrets.secret = {
            enable = true;
            name = "secret";
            file = "encrypted-input";
            path = "$XDG_RUNTIME_DIR/current/secret";
            symlink = true;
            mode = "0400";
            trimFinalNewline = false;
          };
        };
        ageBin = toString recordingAge;
        locale = "C";
      };
    in
    pkgs.writeShellApplication {
      name = "test-identity-order";
      runtimeInputs = [ pkgs.coreutils ];
      text = ''
        ${installer.prepareIdentities}
        ${installer.newGeneration}
        ${installer.installSecrets}
        true
      '';
    };
  paths = [
    "${identities}/first identity"
    "${identities}/second identity"
  ];
  ordered = lib.getExe (script "ordered" paths);
  together = lib.getExe (script "all" paths);
  unavailable = lib.getExe (script "ordered" [ "${identities}/first identity" ]);
in
pkgs.runCommand "agenix-identity-order" { } ''
  export XDG_RUNTIME_DIR="$PWD/runtime" CALL_LOG="$PWD/calls"
  mkdir "$XDG_RUNTIME_DIR"
  mkdir -p "$XDG_RUNTIME_DIR/generations/1"
  printf stale > "$XDG_RUNTIME_DIR/generations/1/secret.tmp"
  : > "$CALL_LOG"
  install -m600 ${../example/secret1.age} encrypted-input
  ${ordered}
  test "$(cat "$XDG_RUNTIME_DIR/current/secret")" = hello
  test "$(grep -c '^call$' "$CALL_LOG")" -eq 1
  grep -Fx ${lib.escapeShellArg "${identities}/first identity"} "$CALL_LOG"
  if grep -Fx ${lib.escapeShellArg "${identities}/second identity"} "$CALL_LOG"; then exit 1; fi

  : > "$CALL_LOG"
  install -m600 ${../example/secret2.age} encrypted-input
  ${ordered}
  test "$(cat "$XDG_RUNTIME_DIR/current/secret")" = 'world!'
  test "$(grep -c '^call$' "$CALL_LOG")" -eq 2
  test "$(tail -n 1 "$CALL_LOG")" = ${lib.escapeShellArg "${identities}/second identity"}

  # The next attempt must work even if the failed backend left partial output.
  export FAIL_FIRST=1
  ${ordered}
  test "$(cat "$XDG_RUNTIME_DIR/current/secret")" = 'world!'
  old="$(readlink "$XDG_RUNTIME_DIR/current")"
  if ${unavailable}; then exit 1; fi
  test "$(readlink "$XDG_RUNTIME_DIR/current")" = "$old"
  test "$(cat "$XDG_RUNTIME_DIR/current/secret")" = 'world!'
  test -z "$(find "$XDG_RUNTIME_DIR" -name '*.tmp' -print)"
  unset FAIL_FIRST

  : > "$CALL_LOG"
  ${together}
  test "$(grep -c '^call$' "$CALL_LOG")" -eq 1
  test "$(wc -l < "$CALL_LOG")" -eq 3
  test "$(cat "$XDG_RUNTIME_DIR/current/secret")" = 'world!'
  touch "$out"
''
