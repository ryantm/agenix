{
  lib,
  stdenvNoCC,
  age,
  jq,
  nix,
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
stdenvNoCC.mkDerivation rec {
  pname = "agenix";
  version = "0.15.0";
  src = replaceVars ./agenix.sh {
    inherit ageBin version;
    jqBin = "${jq}/bin/jq";
    nixInstantiate = "${nix}/bin/nix-instantiate";
    mktempBin = "${coreutils}/bin/mktemp";
    diffBin = "${diffutils}/bin/diff";
    sshKeygenBin = "${openssh}/bin/ssh-keygen";
    base64Bin = "${coreutils}/bin/base64";
    headBin = "${coreutils}/bin/head";
    trBin = "${coreutils}/bin/tr";
    sedBin = "${gnused}/bin/sed";
  };
  dontUnpack = true;
  doInstallCheck = true;
  installCheckInputs = [ coreutils ] ++ lib.optional runShellcheck shellcheck;
  postInstallCheck = ''
    ${lib.optionalString runShellcheck "shellcheck --norc --enable=all ${bin}"}
    ${bin} -h | grep ${version}
    bash ${../test/cli.sh} ${bin} ${../example} ${../example_keys} ${../test/fixtures/one-way/agenix-rules.nix}
  '';

  installPhase = ''
    install -D $src ${bin}
  '';

  meta.description = "age-encrypted secrets for NixOS";
}
