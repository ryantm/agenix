{ pkgs }:
let
  keyName = "domain\\tuser's \"key\" $HOME `id` $(id)";
  identityFiles = pkgs.runCommand "agenix-identity-fixtures" { } ''
    mkdir "$out"
    touch "$out/empty"
    printf key > "$out"/${pkgs.lib.escapeShellArg keyName}
  '';
  key = "${identityFiles}/${keyName}";
  installer = (import ../modules/secret-install.nix { inherit (pkgs) lib; }).installer {
    cfg = {
      verbosity = "quiet";
      secretsDir = "\${XDG_RUNTIME_DIR}/agenix";
      secretsMountPoint = "\${XDG_RUNTIME_DIR}/agenix.d";
      identityPaths = [
        "${identityFiles}/missing"
        "${identityFiles}/empty"
        key
      ];
      secrets.example = {
        enable = true;
        name = "example";
        file = "$XDG_RUNTIME_DIR/encrypted";
        path = "$XDG_RUNTIME_DIR/custom/example";
        mode = "0400";
        symlink = true;
      };
    };
    ageBin = "$XDG_RUNTIME_DIR/mock-age";
    locale = "C";
  };
in
pkgs.runCommand "agenix-shared-installer-test" { } ''
  set -eu
  export XDG_RUNTIME_DIR="$PWD/runtime"
  mkdir -p "$XDG_RUNTIME_DIR"
  echo first > "$XDG_RUNTIME_DIR/encrypted"
  cat > "$XDG_RUNTIME_DIR/mock-age" <<'EOF'
  #!${pkgs.runtimeShell}
  set -eu
  test "$1" = --decrypt
  shift
  test "$1" = -i
  test "$2" = ${pkgs.lib.escapeShellArg key}
  shift 2
  test "$1" = -o
  cp "$3" "$2"
  EOF
  chmod +x "$XDG_RUNTIME_DIR/mock-age"

  run_install() {
    ${installer.newGeneration}
    ${installer.installSecrets}
    true
  }

  run_install 2> "$XDG_RUNTIME_DIR/warnings"
  grep -F ${pkgs.lib.escapeShellArg "entry ${identityFiles}/missing not present!"} "$XDG_RUNTIME_DIR/warnings"
  test "$(cat "$XDG_RUNTIME_DIR/custom/example")" = first
  test "$(readlink "$XDG_RUNTIME_DIR/agenix")" = "$XDG_RUNTIME_DIR/agenix.d/1"
  test "$(stat -c %a "$XDG_RUNTIME_DIR/agenix.d/1/example")" = 400

  echo second > "$XDG_RUNTIME_DIR/encrypted"
  run_install 2> "$XDG_RUNTIME_DIR/warnings"
  test "$(cat "$XDG_RUNTIME_DIR/custom/example")" = second
  test "$(readlink "$XDG_RUNTIME_DIR/agenix")" = "$XDG_RUNTIME_DIR/agenix.d/2"
  test ! -e "$XDG_RUNTIME_DIR/agenix.d/1"
  mkdir -p "$out"
''
