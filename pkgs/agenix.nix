{
  lib,
  stdenv,
  rage,
  jq,
  nix,
  mktemp,
  diffutils,
  substituteAll,
  ageBin ? "${rage}/bin/rage",
  shellcheck,
}: let
  bin = "${placeholder "out"}/bin/agenix";
in
  stdenv.mkDerivation rec {
    pname = "agenix";
    version = "0.15.0";
    src = substituteAll {
      inherit ageBin version;
      jqBin = "${jq}/bin/jq";
      nixInstantiate = "${nix}/bin/nix-instantiate";
      mktempBin = "${mktemp}/bin/mktemp";
      diffBin = "${diffutils}/bin/diff";
      src = ./agenix.sh;
    };
    dontUnpack = true;
    doInstallCheck = true;
    installCheckInputs = [shellcheck];
    postInstallCheck = ''
      shellcheck ${bin}
      ${bin} -h | grep ${version}

      mkdir -p /tmp/home/.ssh
      cp -r "${../example}" /tmp/home/secrets
      chmod -R u+rw /tmp/home/secrets
      export HOME=/tmp/home
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

      cd /tmp/home/secrets
      test $(${bin} -d secret1.age) = "hello"
    '';

    installPhase = ''
      install -D $src ${bin}
    '';

    meta.description = "age-encrypted secrets for NixOS";
  }
