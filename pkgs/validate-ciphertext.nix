{ age }:
age.overrideAttrs (old: {
  pname = "agenix-validate";
  postPatch = (old.postPatch or "") + ''
    mkdir -p cmd/agenix-validate
    cp ${./validate-ciphertext.go} cmd/agenix-validate/main.go
  '';
  subPackages = [ "cmd/agenix-validate" ];
  ldflags = [
    "-s"
    "-w"
  ];
  preInstall = "";
  doCheck = false;
  doInstallCheck = false;
  meta = old.meta // {
    description = "Check the public structure of age ciphertext";
    mainProgram = "agenix-validate";
  };
})
