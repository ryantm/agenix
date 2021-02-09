{stdenv, rustPlatform, fetchFromGitHub, installShellFiles, darwin }:

rustPlatform.buildRustPackage rec {
  pname = "rage";
  version = "unstable-2020-09-05";

  src = fetchFromGitHub {
    owner = "str4d";
    repo = pname;
    rev = "8368992e60cbedb2d6b725c3e25440e65d8544d1";
    sha256 = "sha256-ICcApZQrR4hGxo/RcFMktenE4dswAXA2/nJ5D++O2ig=";
  };

  cargoSha256 = "sha256-QwNtp7Hxsiads3bh8NRra25RdPbIdjp+pSWTllAvdmQ=";

  nativeBuildInputs = [ installShellFiles ];

  buildInputs = stdenv.lib.optionals stdenv.isDarwin [ 
    darwin.Security
    darwin.apple_sdk.frameworks.Foundation
  ];

  postBuild = ''
    cargo run --example generate-docs
    cargo run --example generate-completions
  '';

  postInstall = ''
    installManPage target/manpages/*
    installShellCompletion target/completions/*.{bash,fish,zsh}
  '';

  meta = with stdenv.lib; {
    description = "A simple, secure and modern encryption tool with small explicit keys, no config options, and UNIX-style composability";
    homepage = "https://github.com/str4d/rage";
    changelog = "https://github.com/str4d/rage/releases/tag/v${version}";
    license = licenses.asl20;
    maintainers = [ maintainers.marsam ];
  };
}
