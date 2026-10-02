{ pkgs }:
let
  names = [
    "unchanged"
    "lf"
    "crlf"
    "double"
    "empty"
    "plain"
    "binary"
    "nul"
  ];
  installer = (import ../modules/secret-install.nix { inherit (pkgs) lib; }).installer {
    cfg = {
      verbosity = "quiet";
      secretsDir = "$XDG_RUNTIME_DIR/secrets";
      secretsMountPoint = "$XDG_RUNTIME_DIR/generations";
      identityPaths = [ "${pkgs.writeText "test-identity" "test-only"}" ];
      secrets = pkgs.lib.genAttrs names (name: {
        enable = true;
        inherit name;
        file = "$XDG_RUNTIME_DIR/inputs/${name}";
        path = "$XDG_RUNTIME_DIR/secrets/${name}";
        mode = "0400";
        symlink = true;
        trimFinalNewline = name != "unchanged" && name != "binary";
      });
    };
    ageBin = "$XDG_RUNTIME_DIR/mock-age";
    locale = "C";
  };
in
pkgs.runCommand "agenix-trim-newline-test" { } ''
  set -eu
  export XDG_RUNTIME_DIR="$PWD/runtime"
  mkdir -p "$XDG_RUNTIME_DIR/inputs" "$XDG_RUNTIME_DIR/expected"
  printf 'token\n' > "$XDG_RUNTIME_DIR/inputs/unchanged"
  printf 'token\n' > "$XDG_RUNTIME_DIR/inputs/lf"
  printf 'token\r\n' > "$XDG_RUNTIME_DIR/inputs/crlf"
  printf 'first\nsecond\n\n' > "$XDG_RUNTIME_DIR/inputs/double"
  touch "$XDG_RUNTIME_DIR/inputs/empty"
  printf 'token' > "$XDG_RUNTIME_DIR/inputs/plain"
  printf '\000\377\r\n' > "$XDG_RUNTIME_DIR/inputs/binary"
  printf 'token\000' > "$XDG_RUNTIME_DIR/inputs/nul"

  cp "$XDG_RUNTIME_DIR/inputs/unchanged" "$XDG_RUNTIME_DIR/expected/unchanged"
  printf token > "$XDG_RUNTIME_DIR/expected/lf"
  printf token > "$XDG_RUNTIME_DIR/expected/crlf"
  printf 'first\nsecond\n' > "$XDG_RUNTIME_DIR/expected/double"
  touch "$XDG_RUNTIME_DIR/expected/empty"
  printf token > "$XDG_RUNTIME_DIR/expected/plain"
  cp "$XDG_RUNTIME_DIR/inputs/binary" "$XDG_RUNTIME_DIR/expected/binary"
  cp "$XDG_RUNTIME_DIR/inputs/nul" "$XDG_RUNTIME_DIR/expected/nul"

  cat > "$XDG_RUNTIME_DIR/mock-age" <<'EOF'
  #!${pkgs.runtimeShell}
  set -eu
  test "$1" = --decrypt
  test "$2" = -i
  test "$4" = -o
  cat "$6" > "$5"
  test "$(stat -c %a "$5")" = 400
  EOF
  chmod +x "$XDG_RUNTIME_DIR/mock-age"

  ${installer.newGeneration}
  ${installer.installSecrets}

  for name in ${pkgs.lib.escapeShellArgs names}; do
    cmp "$XDG_RUNTIME_DIR/secrets/$name" "$XDG_RUNTIME_DIR/expected/$name"
    test "$(stat -Lc %a "$XDG_RUNTIME_DIR/secrets/$name")" = 400
  done
  touch "$out"
''
