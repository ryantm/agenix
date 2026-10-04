{
  lib,
  stdenv,
  age,
  jq,
  nix,
  mktemp,
  diffutils,
  coreutils,
  openssh,
  gnused,
  replaceVars,
  ageBin ? "${age}/bin/age",
  shellcheck,
  runShellcheck ? true,
}:
let
  bin = "${placeholder "out"}/bin/agenix";
in
stdenv.mkDerivation rec {
  pname = "agenix";
  version = "0.15.0";
  src = replaceVars ./agenix.sh {
    inherit ageBin version;
    jqBin = "${jq}/bin/jq";
    nixInstantiate = "${nix}/bin/nix-instantiate";
    mktempBin = "${mktemp}/bin/mktemp";
    diffBin = "${diffutils}/bin/diff";
    sshKeygenBin = "${openssh}/bin/ssh-keygen";
    base64Bin = "${coreutils}/bin/base64";
    headBin = "${coreutils}/bin/head";
    trBin = "${coreutils}/bin/tr";
    sedBin = "${gnused}/bin/sed";
  };
  dontUnpack = true;
  doInstallCheck = true;
  installCheckInputs = lib.optional runShellcheck shellcheck;
  postInstallCheck = ''
    ${lib.optionalString runShellcheck "shellcheck --norc --enable=all ${bin}"}
    ${bin} -h | grep ${version}

    test_tmp=$(mktemp -d 2>/dev/null || mktemp -d -t 'mytmpdir')
    export HOME="$test_tmp/home"
    export NIX_STORE_DIR="$test_tmp/nix/store"
    export NIX_STATE_DIR="$test_tmp/nix/var"
    mkdir -p "$HOME" "$NIX_STORE_DIR" "$NIX_STATE_DIR"
    function cleanup {
      rm -rf "$test_tmp"
    }
    trap "cleanup" 0 2 3 15

    mkdir -p $HOME/.ssh
    cp -r "${../example}" $HOME/secrets
    chmod -R u+rw $HOME/secrets
    (
    umask u=rw,g=r,o=r
    cp ${../example_keys/user1.pub} $HOME/.ssh/id_ed25519.pub
    chown $UID $HOME/.ssh/id_ed25519.pub
    )
    (
    umask u=rw,g=,o=
    cp ${../example_keys/user1} $HOME/.ssh/id_ed25519
    chown $UID $HOME/.ssh/id_ed25519
    )

    cd $HOME/secrets
    test $(${bin} -d secret1.age) = "hello"
    ${bin} --check

    # An identity from a pipe is read once and used for every file of a rekey.
    identity="$HOME/.ssh/id_ed25519"
    mv "$identity" "$HOME/identity"
    test $(${bin} -d secret1.age -i <(cat "$HOME/identity")) = "hello"
    test $(cat "$HOME/identity" | ${bin} -d secret1.age -i /dev/stdin) = "hello"
    before=$(sha256sum secret1.age secret2.age)
    export TMPDIR="$test_tmp/agenix-tmp"
    mkdir "$TMPDIR"
    ${bin} -r -i <(cat "$HOME/identity") 2> rekey-log
    test "$before" != "$(sha256sum secret1.age secret2.age)"
    grep -q 'rekeying secret2.age' rekey-log
    test $(${bin} -d secret1.age -i <(cat "$HOME/identity")) = "hello"
    test -z "$(ls -A "$TMPDIR")"
    if ${bin} -d secret1.age -i <(true) 2> empty-log; then
      echo 'agenix -i should fail for an empty pipe' >&2
      exit 1
    fi
    grep -q 'is empty' empty-log
    unset TMPDIR
    mv "$HOME/identity" "$identity"
    sed 's/"secret2.age".publicKeys = \[ user1 \];/"secret2.age".publicKeys = [ system1 ];/' secrets.nix > changed-rules.nix
    if AGENIX_RULES=changed-rules.nix ${bin} --check > check-report; then
      echo 'agenix --check should fail when recipients differ' >&2
      exit 1
    fi
    grep -q '^✗ secret2.age$' check-report
    grep -q '^  missing: ssh-ed25519 ' check-report
    grep -q '^  extra: ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAIL0idNvgGiucWgup/mP78zyC23uFjYq0evcWdjGQUaBH$' check-report
  '';

  installPhase = ''
    install -D $src ${bin}
  '';

  meta.description = "age-encrypted secrets for NixOS";
}
