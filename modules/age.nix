{ config, lib, pkgs, ... }:

with lib;
let
  cfg = config.age;

  rage = pkgs.callPackage ../pkgs/rage.nix { };
  ageBin = "${rage}/bin/rage";

  minisign = pkgs.minisign;
  minisignBin = "${minisign}/bin/minisign";

  users = config.users.users;

  identities = builtins.concatStringsSep " " (map (path: "-i ${path}") cfg.sshKeyPaths);

  installSecret = secretType: ''
    _invalid=0
    ${verifySecret secretType}

    if (( _invalid == 0 )); then
    ${decryptSecret secretType}
    fi
  '';

  decryptSecret = secretType: ''
    echo "decrypting ${secretType.file} to ${secretType.path}..."
    TMP_FILE="${secretType.path}.tmp"
    mkdir -p $(dirname ${secretType.path})
    (umask 0400; ${ageBin} --decrypt ${identities} -o "$TMP_FILE" "${secretType.file}")
    chmod ${secretType.mode} "$TMP_FILE"
    chown ${secretType.owner}:${secretType.group} "$TMP_FILE"
    mv -f "$TMP_FILE" '${secretType.path}'
  '';

  verifySecret = secretType:
    let
      signature =
        if secretType.signature.pubKeyFile != null then
          "-p ${secretType.signature.pubKeyFile}"
        else if secretType.signature.pubKey != null then
          "-P ${secretType.signature.pubKey}"
        else
          throw "To verify a file's contents, either the pubKeyFile or pubKey options must be set.";

      sigfile =
        if secretType.signature.file != null then
          secretType.signature.file
        else
          throw "A signature file is required in order to verify a file's contents.";
    in
    lib.optionalString (secretType.signature != null) ''
      echo "verifying ${secretType.file}..."
      ${minisignBin} -Vm ${secretType.file} ${signature} -x ${sigfile}
      _invalid=$?
    '';

  rootOwnedSecrets = builtins.filter
    (st: st.owner == "root" && st.group == "root")
    (builtins.attrValues cfg.secrets);
  installRootOwnedSecrets = builtins.concatStringsSep "\n"
    ([ "echo '[agenix] decrypting root secrets...'" ] ++ (map installSecret rootOwnedSecrets));

  nonRootSecrets = builtins.filter
    (st: st.owner != "root" || st.group != "root")
    (builtins.attrValues cfg.secrets);
  installNonRootSecrets = builtins.concatStringsSep "\n"
    ([ "echo '[agenix] decrypting non-root secrets...'" ] ++ (map installSecret nonRootSecrets));

  secretType = types.submodule ({ config, ... }: {
    options = {
      name = mkOption {
        type = types.str;
        default = config._module.args.name;
        description = ''
          Name of the file used in /run/secrets
        '';
      };
      file = mkOption {
        type = types.path;
        description = ''
          Age file the secret is loaded from.
        '';
      };
      path = mkOption {
        type = types.str;
        default = "/run/secrets/${config.name}";
        description = ''
          Path where the decrypted secret is installed.
        '';
      };
      mode = mkOption {
        type = types.str;
        default = "0400";
        description = ''
          Permissions mode of the in octal.
        '';
      };
      owner = mkOption {
        type = types.str;
        default = "root";
        description = ''
          User of the file.
        '';
      };
      group = mkOption {
        type = types.str;
        default = users.${config.owner}.group;
        description = ''
          Group of the file.
        '';
      };
      signature = mkOption {
        type = types.nullOr (types.submodule ({ ... }: {
          options = {
            pubKeyFile = mkOption {
              type = with types; nullOr path;
              default = cfg.defaultPubKeyFile;
              description = ''
                Public key file used to verify the secret.
              '';
            };
            pubKey = mkOption {
              type = with types; nullOr str;
              default = cfg.defaultPubKey;
              description = ''
                Public key used to verify the secret.
              '';
            };
            file = mkOption {
              type = with types; nullOr path; # TODO: support strs as relative path
              default = null;
              description = ''
                File containing the signature of the secret.
              '';
            };
          };
        }));
        default = null;
        description = ''
          Options for configuring signature verification of secrets.
        '';
      };
    };
  });
in
{
  options.age = {
    secrets = mkOption {
      type = types.attrsOf secretType;
      default = { };
      description = ''
        Attrset of secrets.
      '';
    };
    sshKeyPaths = mkOption {
      type = types.listOf types.path;
      default =
        if config.services.openssh.enable then
          map (e: e.path) (lib.filter (e: e.type == "rsa" || e.type == "ed25519") config.services.openssh.hostKeys)
        else [ ];
      description = ''
        Path to SSH keys to be used as identities in age decryption.
      '';
    };
    defaultPubKey = mkOption {
      type = with types; nullOr str;
      default = null;
      description = ''
        The default public key used to verify signatures.
      '';
    };
    defaultPubKeyFile = mkOption {
      type = with types; nullOr path;
      default = null;
      description = ''
        The default public key file used to verify signatures.
      '';
    };
  };
  config = mkIf (cfg.secrets != { }) {
    assertions = [{
      assertion = cfg.sshKeyPaths != [ ];
      message = "age.sshKeyPaths must be set.";
    }];

    # Secrets with root owner and group can be installed before users
    # exist. This allows user password files to be encrypted.
    system.activationScripts.agenixRoot = installRootOwnedSecrets;
    system.activationScripts.users.deps = [ "agenixRoot" ];

    # Other secrets need to wait for users and groups to exist.
    system.activationScripts.agenix = stringAfter [ "users" "groups" ] installNonRootSecrets;
  };
}
