{ lib, rustPlatform, fetchFromGitHub, pkgconfig, pcsclite }:

rustPlatform.buildRustPackage rec {
  pname = "age-plugin-yubikey";
  version = "0.1.0";

  src = fetchFromGitHub {
    owner = "str4d";
    repo = pname;
    rev = "v${version}";
    sha256 = "sha256-9EvNphIe6wXuVuEWZvDINz2S74OInubBw7Kq/OamRdY=";
  };

  cargoSha256 = "sha256-0o/M2B14UJKxPbpzphxXnoKOGUbudLPbYO4lvxqUlX4=";

  nativeBuildInputs = [ pkgconfig ];
  buildInputs = [ pcsclite ];

  meta = with lib; {
    description = "YubiKey plugin for age";
    homepage = "https://github.com/str4d/${pname}";
    changelog = "https://github.com/str4d/${pname}/releases/tag/v${version}";
    license = with licenses; [ asl20 mit ]; # either at your option
    maintainers = with maintainers; [ marsam ryantm ];
  };
}
