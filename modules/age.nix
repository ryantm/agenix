{ config, options, lib, utils, pkgs, ... }:

with lib;

let
  cfg = config.age;

  # we need at least rage 0.5.0 to support ssh keys
  rage =
    if lib.versionOlder pkgs.rage.version "0.5.0"
    then pkgs.callPackage ../pkgs/rage.nix { }
    else pkgs.rage;
  ageBin = config.age.ageBin;

  users = config.users.users;

  identities = builtins.concatStringsSep " " (map (path: "-i ${path}") cfg.identityPaths);
  installSecret = secretType: ''
    ${if secretType.symlink then ''
      _truePath="${cfg.secretsMountPoint}/$_agenix_generation/${secretType.name}"
    '' else ''
      _truePath="${secretType.path}"
    ''}
    echo "decrypting '${secretType.file}' to '$_truePath'..."
    TMP_FILE="$_truePath.tmp"
    mkdir -p "$(dirname "$_truePath")"
    [ "${secretType.path}" != "${cfg.secretsDir}/${secretType.name}" ] && mkdir -p "$(dirname "${secretType.path}")"
    (
      umask u=r,g=,o=
      test -f "${secretType.file}" || echo '[agenix] WARNING: encrypted file ${secretType.file} does not exist!'
      test -d "$(dirname "$TMP_FILE")" || echo "[agenix] WARNING: $(dirname "$TMP_FILE") does not exist!"
      LANG=${config.i18n.defaultLocale} ${ageBin} --decrypt ${identities} -o "$TMP_FILE" "${secretType.file}"
    )
    chmod ${secretType.mode} "$TMP_FILE"
    chown ${secretType.owner}:${secretType.group} "$TMP_FILE"

    # path to the old version of the secret. cfg.secretsDir has already been
    # updated to point at the latest generation, so we have to revert those
    # paths.
    outputPath="${cfg.secretsDir}/"
    currentGenerationPath="${cfg.secretsMountPoint}/$_agenix_generation/"
    previousGenerationPath="${cfg.secretsMountPoint}/$(( _agenix_generation - 1 ))/"
    _oldPath=$(realpath ${secretType.path})
    _oldPath=''${_oldPath/#$currentGenerationPath/$previousGenerationPath}
    _oldPath=''${_oldPath/#$outputPath/$previousGenerationPath}
    [ -f $_oldPath ] && {
      changes=$(${lib.concatStringsSep " " [
        "${pkgs.rsync}/bin/rsync"
        "--dry-run -i" # just print what changed, don't do anything
        "-aHAX"        # care about everything (e.g. file permissions)
        "--no-t -c"    # but don't care about last modified timestamps
        "$TMP_FILE" "$_oldPath"
      ]})
    } || changes=true # _oldPath doesn't exist, so count it as a change

    mv -f "$TMP_FILE" "$_truePath"

    ${optionalString secretType.symlink ''
      [ "${secretType.path}" != "${cfg.secretsDir}/${secretType.name}" ] && ln -sfn "${cfg.secretsDir}/${secretType.name}" "${secretType.path}"
    ''}

    # if /run/nixos doesn't exist, this is boot up and we don't need to activate the scripts.
    [ "$changes" != "" ] && [ -d "/run/nixos" ] && {
      echo '${lib.concatStringsSep "\n" secretType.reloadUnits}' >> /run/nixos/activation-reload-list
      echo '${lib.concatStringsSep "\n" secretType.restartUnits}' >> /run/nixos/activation-restart-list
      ${secretType.onChange}
    }
  '';

  testIdentities = map (path: ''
    test -f ${path} || echo '[agenix] WARNING: config.age.identityPaths entry ${path} not present!'
    '') cfg.identityPaths;

  isRootSecret = st: (st.owner == "root" || st.owner == "0") && (st.group == "root" || st.group == "0");
  isNotRootSecret = st: !(isRootSecret st);

  rootOwnedSecrets = builtins.filter isRootSecret (builtins.attrValues cfg.secrets);
  installRootOwnedSecrets = builtins.concatStringsSep "\n" ([ "echo '[agenix] decrypting root secrets...'" ] ++ testIdentities ++ (map installSecret rootOwnedSecrets));

  nonRootSecrets = builtins.filter isNotRootSecret (builtins.attrValues cfg.secrets);
  installNonRootSecrets = builtins.concatStringsSep "\n" ([ "echo '[agenix] decrypting non-root secrets...'" ] ++ (map installSecret nonRootSecrets));

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
      owner = mkOption {
        type = types.str;
        default = "0";
        description = ''
          User of the decrypted secret.
        '';
      };
      group = mkOption {
        type = types.str;
        default = users.${config.owner}.group or "0";
        description = ''
          Group of the decrypted secret.
        '';
      };
      onChange = mkOption {
        type = types.str;
        default = "";
        description = "A script to run when secret is updated.";
      };
      reloadUnits = mkOption {
        type = types.listOf utils.systemdUtils.lib.unitNameType;
        default = [];
        description = "The systemd services to reload when the secret changes.";
        example = literalExpression ''[ "wireguard-wg0.service" ]'';
      };
      restartUnits = mkOption {
        type = types.listOf utils.systemdUtils.lib.unitNameType;
        default = [];
        description = "The systemd services to restart when the secret changes.";
        example = literalExpression ''[ "wireguard-wg0.service" ]'';
      };
      symlink = mkEnableOption "symlinking secrets to their destination" // { default = true; };
    };
  });
in
{

  imports = [
    (mkRenamedOptionModule [ "age" "sshKeyPaths" ] [ "age" "identityPaths" ])
  ];

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
      type = types.path;
      default = "/run/agenix";
      description = ''
        Folder where secrets are symlinked to
      '';
    };
    secretsMountPoint = mkOption {
      type = types.addCheck types.str
        (s:
          (builtins.match "[ \t\n]*" s) == null # non-empty
            && (builtins.match ".+/" s) == null) # without trailing slash
      // { description = "${types.str.description} (with check: non-empty without trailing slash)"; };
      default = "/run/agenix.d";
      defaultText = "/run/agenix.d";
      description = ''
        Where secrets are created before they are symlinked to ''${cfg.secretsDir}
      '';
    };
    identityPaths = mkOption {
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

  config = mkIf (cfg.secrets != { }) {
    assertions = [{
      assertion = cfg.identityPaths != [ ];
      message = "age.identityPaths must be set.";
    }];

    # Create a new directory full of secrets for symlinking (this helps
    # ensure removed secrets are actually removed, or at least become
    # invalid symlinks).
    system.activationScripts.agenixMountSecrets = {
      text = ''
        _agenix_generation="$(basename "$(readlink ${cfg.secretsDir})" || echo 0)"
        (( ++_agenix_generation ))
        echo "[agenix] symlinking new secrets to ${cfg.secretsDir} (generation $_agenix_generation)..."
        mkdir -p "${cfg.secretsMountPoint}"
        chmod 0751 "${cfg.secretsMountPoint}"
        grep -q "${cfg.secretsMountPoint} ramfs" /proc/mounts || mount -t ramfs none "${cfg.secretsMountPoint}" -o nodev,nosuid,mode=0751
        mkdir -p "${cfg.secretsMountPoint}/$_agenix_generation"
        chmod 0751 "${cfg.secretsMountPoint}/$_agenix_generation"
        ln -sfn "${cfg.secretsMountPoint}/$_agenix_generation" ${cfg.secretsDir}
      '';
      deps = [
        "specialfs"
      ];
    };

    # Secrets with root owner and group can be installed before users
    # exist. This allows user password files to be encrypted.
    system.activationScripts.agenixRoot = {
      text = installRootOwnedSecrets;
      deps = [ "agenixMountSecrets" "specialfs" ];
    };
    system.activationScripts.users.deps = [ "agenixRoot" ];

    # chown the secrets mountpoint and the current generation to the keys group
    # instead of leaving it root:root.
    system.activationScripts.agenixChownKeys = {
      text = ''
        chown :keys "${cfg.secretsMountPoint}" "${cfg.secretsMountPoint}/$_agenix_generation"
      '';
      deps = [
        "users"
        "groups"
        "agenixMountSecrets"
      ];
    };

    # Other secrets need to wait for users and groups to exist.
    system.activationScripts.agenixNonRoot = {
      text = installNonRootSecrets;
      deps = [
        "users"
        "groups"
        "specialfs"
        "agenixMountSecrets"
        "agenixChownKeys"
      ];
    };

    # named "agenix" for others to depend on the last activationScript (and thereby all the rest)
    system.activationScripts.agenix = {
      # cleanup old generation
      text = ''
        (( _agenix_generation > 1 )) && {
          echo "[agenix] removing old secrets (generation $(( _agenix_generation - 1 )))..."
          rm -rf "${cfg.secretsMountPoint}/$(( _agenix_generation - 1 ))"
        }
      '';
      deps = [
        "specialfs"
        "agenixMountSecrets"
        "agenixRoot"
        "agenixNonRoot"
      ];
    };
  };
}
