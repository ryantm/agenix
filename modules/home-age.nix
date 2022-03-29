{ config, options, lib, pkgs, ... }:

with lib;

let
  cfg = config.age;

  # we need at least rage 0.5.0 to support ssh keys
  rage =
    if lib.versionOlder pkgs.rage.version "0.5.0"
    then pkgs.callPackage ../pkgs/rage.nix { }
    else pkgs.rage;
  ageBin = "${rage}/bin/rage";

  identities = builtins.concatStringsSep " " (map (path: "-i ${path}") cfg.identityPaths);

  installSecret = secretType: ''
    _truePath="${secretType.path}"
    echo "decrypting '${secretType.file}' to '$_truePath'..."
    TMP_FILE="$_truePath.tmp"
    mkdir -p "$(dirname "$_truePath")"
    [ "${secretType.path}" != "${cfg.secretsDir}/${secretType.name}" ] && mkdir -p "$(dirname "${secretType.path}")"
    (
      umask u=r,g=,o=
      test -f "${secretType.file}" || echo '[agenix] WARNING: encrypted file ${secretType.file} does not exist!'
      test -d "$(dirname "$TMP_FILE")" || echo "[agenix] WARNING: $(dirname "$TMP_FILE") does not exist!"
      ${if config.home.language.base != null then "LANG=${config.home.language.base}" else ""} ${ageBin} --decrypt ${identities} -o "$TMP_FILE" "${secretType.file}"
    )
    chmod ${secretType.mode} "$TMP_FILE"
    chown ${config.home.username}:${secretType.group} "$TMP_FILE"
    mv -f "$TMP_FILE" "$_truePath"
    ${optionalString secretType.symlink ''
      [ "${secretType.path}" != "${cfg.secretsDir}/${secretType.name}" ] && ln -sfn "${cfg.secretsDir}/${secretType.name}" "${secretType.path}"
    ''}
  '';

  testIdentities = map
    (path: ''
      test -f ${path} || echo '[agenix] WARNING: config.age.identityPaths entry ${path} not present!'
    '')
    cfg.identityPaths;

  installSecrets = builtins.concatStringsSep "\n" ([ "echo '[agenix] decrypting user secrets...'" ] ++ (map installSecret (builtins.attrValues cfg.secrets)));

  secretType = types.submodule ({ config, ... }: {
    options = {
      name = mkOption {
        type = types.str;
        default = config._module.args.name;
        description = ''
          Name of the file used in ''${cfg.secretsDir}
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
        default = "${cfg.secretsDir}/${config.name}";
        description = ''
          Path where the decrypted secret is installed.
        '';
      };
      mode = mkOption {
        type = types.str;
        default = "0400";
        description = ''
          Permissions mode of the decrypted secret in a format understood by chmod.
        '';
      };
      # Don't know how to make it find config.home.username becayse this "age" module is a "submodule"
      #  owner = mkOption {
      #    type = types.str;
      #    readOnly = true;
      #    default = "${config.home.username}";
      #    description = ''
      #      User of the decrypted secret.
      #    '';
      #  };
      group = mkOption {
        type = types.str;
        default = "$(id -gn)";
        description = ''
          Group of the decrypted secret.
        '';
      };
      symlink = mkEnableOption "symlinking secrets to their destination" // { default = true; };
    };
  });
in
{
  options.age = {
    ageBin = mkOption {
      type = types.str;
      default = "${rage}/bin/rage";
      description = ''
        The age executable to use.
      '';
    };
    secrets = mkOption {
      type = types.attrsOf secretType;
      default = { };
      description = ''
        Attrset of secrets.
      '';
    };
    secretsDir = mkOption {
      type = types.str;
      default = "/run/user/$(id -u)/agenix"; # Need to figure out how to expose this path via home-manager options
      description = ''
        Folder where secrets are symlinked to
      '';
    };
    identityPaths = mkOption {
      type = types.listOf types.path;
      default = [ ];
      description = ''
        Path to SSH keys to be used as identities in age decryption.
      '';
    };
  };
  config = mkIf (cfg.secrets != { }) (mkMerge [
    {
      assertions = [{
        assertion = cfg.identityPaths != [ ];
        message = "age.identityPaths must be set.";
      }];

      home.activation.agenix = hm.dag.entryAfter [ "writeBoundary" ] installSecrets;
    }
  ]);
}
