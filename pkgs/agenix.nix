{
  lib,
  age,
  nix,
  rustPlatform,
}:
let
  bin = "${placeholder "out"}/bin/agenix";
in
rustPlatform.buildRustPackage rec {
  pname = "agenix";
  version = "0.1.0";
  src = ./.;
  cargoLock.lockFile = ./Cargo.lock;
  doInstallCheck = true;

  buildInputs = [
    age
    nix
  ];

  postPatch = ''
    # Hardcode dependencies into the rust code, until we use
    # the respective pure rust implementations.
    sed -i 's|= "nix-instantiate"|= "${nix}/bin/nix-instantiate"|' src/nix.rs
    sed -i 's|= "age"|= "${lib.getExe age}"|' src/crypto.rs
  '';

  postInstallCheck = ''
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
  '';

  meta.description = "age-encrypted secrets for NixOS";
}
