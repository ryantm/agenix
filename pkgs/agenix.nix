{
  lib,
  stdenv,
  age,
  jq,
  nix,
  mktemp,
  diffutils,
  substituteAll,
  ageBin ? "${age}/bin/age",
  shellcheck,
}:
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

  doCheck = true;
  checkInputs = [shellcheck];
  postCheck = ''
    shellcheck $src
  '';

  installPhase = ''
    install -D $src ${placeholder "out"}/bin/agenix
  '';

  meta.description = "age-encrypted secrets for NixOS";
}
