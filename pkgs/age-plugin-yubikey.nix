{ lib, rustPlatform, fetchFromGitHub, pkgconfig, pcsclite }:

rustPlatform.buildRustPackage rec {
  pname = "age-plugin-yubikey";
  version = "6042d52";

  src = fetchFromGitHub {
    owner = "str4d";
    repo = pname;
    rev = "6042d5266f94b56d5b0702fe5fae4bbbd631613d";
    sha256 = "sha256-VaDnaV3sVAIPaPiFToJHvgXDN54MN+f24tHARVZ2liQ=";
  };

  cargoSha256 = "sha256-0/h8ZaRtxgfrmwr/bUZ8YvE7iBh81E0I3zopTNS4eMM=";

  nativeBuildInputs = [ pkgconfig ];
  buildInputs = [ pcsclite ];

  meta = with lib; {
    description = "YubiKey plugin for age";
    homepage = "https://github.com/str4d/${pname}";
    changelog = "https://github.com/str4d/${pname}/releases/tag/v${version}";
    license = with licenses; [ asl20 mit ]; # either at your option
    maintainers = with maintainers; [ nrdxp ];
  };
}
