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

  users = config.users.users;

  identities = builtins.concatStringsSep " " (map (path: "-i ${path}") cfg.sshKeyPaths);
  installSecret = secretType: ''
    echo "decrypting ${secretType.file} to ${secretType.path}..."
    TMP_FILE="${secretType.path}.tmp"
    mkdir -p $(dirname ${secretType.path})
    (
      umask u=r,g=,o=
      LANG=${config.i18n.defaultLocale} ${ageBin} --decrypt ${identities} -o "$TMP_FILE" "${secretType.file}"
    )
    chmod ${secretType.mode} "$TMP_FILE"
    chown ${secretType.owner}:${secretType.group} "$TMP_FILE"
    mv -f "$TMP_FILE" '${secretType.path}'
  '';

  isRootSecret = st: (st.owner == "root" || st.owner == "0") && (st.group == "root" || st.group == "0");
  isNotRootSecret = st: !(isRootSecret st);

  rootOwnedSecrets = builtins.filter isRootSecret (builtins.attrValues cfg.secrets);
  installRootOwnedSecrets = builtins.concatStringsSep "\n" ([ "echo '[agenix] decrypting root secrets...'" ] ++ (map installSecret rootOwnedSecrets));

  nonRootSecrets = builtins.filter isNotRootSecret (builtins.attrValues cfg.secrets);
  installNonRootSecrets = builtins.concatStringsSep "\n" ([ "echo '[agenix] decrypting non-root secrets...'" ] ++ (map installSecret nonRootSecrets));

  destinationPaths = map (secret: secret.path) (builtins.attrValues cfg.secrets);
  agenixSystemFilename = "agenix-cache.json";
  agenixSystemFile = pkgs.writeText agenixSystemFilename (builtins.toJSON destinationPaths);

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
        default = "0";
        description = ''
          User of the file.
        '';
      };
      group = mkOption {
        type = types.str;
        default = users.${config.owner}.group or "0";
        description = ''
          Group of the file.
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
  };

  config = mkMerge [

    (mkIf (cfg.secrets != { }) {
      assertions = [{
        assertion = cfg.sshKeyPaths != [ ];
        message = "age.sshKeyPaths must be set.";
      }];

      # Secrets with root owner and group can be installed before users
      # exist. This allows user password files to be encrypted.
      system.activationScripts.agenixRoot = stringAfter [ "specialfs" ] installRootOwnedSecrets;
      system.activationScripts.users.deps = [ "agenixRoot" ];

      # Other secrets need to wait for users and groups to exist.
      system.activationScripts.agenix = stringAfter [ "users" "groups" "specialfs" ] installNonRootSecrets;

      system.extraSystemBuilderCmds = ''
        ln -s ${agenixSystemFile} $out/${agenixSystemFilename}
      '';
    })

    {
      # read from /run/current-system/${agenixSystemFilename} to ensure we are reading the file of
      # the current activated configuration
      system.activationScripts.agenixCleanup = noDepEntry ''
        if [ -f "/run/current-system/${agenixSystemFilename}" ]; then
          echo '[agenix] cleaning up old secrets...'

          files_to_be_removed=($(${pkgs.jq}/bin/jq \
            --null-input \
            --raw-output \
            --argfile current "/run/current-system/${agenixSystemFilename}" \
            --argfile new "${agenixSystemFile}" \
            '$current - $new | .[]'))

          for file in "''${files_to_be_removed[@]}"; do
            echo "removing $file..."
            rm "$file"
            rmdir --ignore-fail-on-non-empty --parents "$(dirname "$file")"
          done
        fi
      '';
    }

  ];

}
