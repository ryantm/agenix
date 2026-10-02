{ pkgs }:
let
  shared = import ../modules/secret-install.nix { inherit (pkgs) lib; };
  identities = pkgs.runCommand "agenix-identity-types" { } ''
    mkdir -p "$out/directory"
    touch "$out/empty"
    printf fixture > "$out/valid"
  '';
  cfg = {
    verbosity = "quiet";
    secretsDir = "$XDG_RUNTIME_DIR/agenix";
    secretsMountPoint = "$XDG_RUNTIME_DIR/generations";
    secrets.example = {
      enable = true;
      name = "example";
      file = "$XDG_RUNTIME_DIR/ciphertext";
      path = "$XDG_RUNTIME_DIR/custom/example";
      mode = "0400";
      trimFinalNewline = false;
      symlink = true;
    };
  };
  makeInstaller =
    identityPaths:
    shared.installer {
      cfg = cfg // {
        inherit identityPaths;
      };
      ageBin = "$XDG_RUNTIME_DIR/mock-age";
      locale = "C";
    };
  bad = makeInstaller [
    "${identities}/missing"
    "${identities}/empty"
    "${identities}/directory"
  ];
  good = makeInstaller [ "${identities}/valid" ];
  script =
    installer:
    pkgs.writeShellScript "agenix-identity-test" ''
      ${installer.prepareIdentities}
      ${installer.newGeneration}
      ${installer.installSecrets}
      true
    '';
in
pkgs.runCommand "agenix-missing-identities" { } ''
  export XDG_RUNTIME_DIR="$PWD/runtime"
  mkdir "$XDG_RUNTIME_DIR"
  printf original > "$XDG_RUNTIME_DIR/ciphertext"
  cat > "$XDG_RUNTIME_DIR/mock-age" <<'EOF'
  #!${pkgs.runtimeShell}
  set -eu
  echo called >> "$XDG_RUNTIME_DIR/backend-calls"
  test "$1" = --decrypt
  test "$2" = -i
  test "$4" = -o
  cp "$6" "$5"
  EOF
  chmod +x "$XDG_RUNTIME_DIR/mock-age"

  if ${script bad} > log 2>&1; then exit 1; fi
  grep -q 'ERROR: no readable, non-empty identity files found!' log
  grep -q 'is not a regular file!' log
  test ! -e "$XDG_RUNTIME_DIR/backend-calls"
  test ! -e "$XDG_RUNTIME_DIR/generations"
  test ! -e "$XDG_RUNTIME_DIR/custom"
  test ! -L "$XDG_RUNTIME_DIR/agenix"

  # The decryption subprocess uses a read-only creation umask. Precreate this
  # test-only counter so repeated backend calls can append to it.
  touch "$XDG_RUNTIME_DIR/backend-calls"
  ${script good}
  test "$(cat "$XDG_RUNTIME_DIR/custom/example")" = original
  test "$(readlink "$XDG_RUNTIME_DIR/agenix")" = "$XDG_RUNTIME_DIR/generations/1"
  printf changed > "$XDG_RUNTIME_DIR/ciphertext"
  if ${script bad} > log 2>&1; then exit 1; fi
  test "$(cat "$XDG_RUNTIME_DIR/custom/example")" = original
  test "$(readlink "$XDG_RUNTIME_DIR/agenix")" = "$XDG_RUNTIME_DIR/generations/1"
  test ! -e "$XDG_RUNTIME_DIR/generations/2"
  test "$(wc -l < "$XDG_RUNTIME_DIR/backend-calls")" -eq 1
  ${script good}
  test "$(cat "$XDG_RUNTIME_DIR/custom/example")" = changed
  touch "$out"
''
