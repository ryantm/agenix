{ pkgs }:
let
  countedNix = pkgs.writeShellScriptBin "nix-instantiate" ''
    echo evaluation >> "$NIX_EVAL_COUNT"
    exec ${pkgs.nix}/bin/nix-instantiate "$@"
  '';
  cli = (pkgs.callPackage ../pkgs/agenix.nix { nix = countedNix; }).overrideAttrs {
    doInstallCheck = false;
  };
in
pkgs.runCommand "agenix-cli-rules"
  {
    nativeBuildInputs = [
      cli
      pkgs.jq
      pkgs.python3
    ];
  }
  ''
    bash ${./cli-rules.sh} ${cli}/bin/agenix ${../example_keys}
    touch "$out"
  ''
