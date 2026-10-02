# Import after both agenix and agenix-rekey's modules. Supply the flake root
# and real public keys; masterIdentity is a runtime path outside the store.
{
  root,
  hostName,
  hostPublicKey,
  masterIdentity,
  masterPublicKey,
}:
{
  age.rekey = {
    hostPubkey = hostPublicKey;
    masterIdentities = [
      {
        identity = masterIdentity;
        pubkey = masterPublicKey;
      }
    ];
    storageMode = "local";
    localStorageDir = root + "/secrets/rekeyed/${hostName}";
  };

  age.generators.ed25519 =
    {
      pkgs,
      lib,
      file,
      ...
    }:
    ''
      set -euo pipefail
      umask 077
      work="$(${pkgs.coreutils}/bin/mktemp -d)"
      trap '${pkgs.coreutils}/bin/rm -rf -- "$work"' EXIT
      ${pkgs.openssh}/bin/ssh-keygen -q -t ed25519 -N "" -f "$work/key"
      ${pkgs.coreutils}/bin/cp "$work/key.pub" ${lib.escapeShellArg "${file}.pub"}
      ${pkgs.coreutils}/bin/cat "$work/key"
    '';

  age.secrets = {
    api-token = {
      rekeyFile = root + "/secrets/api-token.age";
      generator.script = { pkgs, ... }: "${pkgs.openssl}/bin/openssl rand -base64 48";
    };
    deploy-key = {
      rekeyFile = root + "/secrets/deploy-key.age";
      generator.script = "ed25519";
    };
  };
}
