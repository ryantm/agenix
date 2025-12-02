{
  stdenvNoCC,
  mmdoc,
  self,
}:
stdenvNoCC.mkDerivation rec {
  name = "agenix-doc";
  src = ../doc;
  phases = [ "mmdocPhase" ];
  mmdocPhase = "${mmdoc}/bin/mmdoc agenix $src $out";
}
