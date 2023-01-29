{
  lib,
  stdenv,
  rage,
  gnused,
  nix,
  mktemp,
  diffutils,
  substituteAll,
  ageBin ? "${rage}/bin/rage",
  shellcheck,
}:
stdenv.mkDerivation rec {
  pname = "agenix";
  version = "0.13.0";
  src = substituteAll {
    inherit ageBin version;
    sedBin = "${gnused}/bin/sed";
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
