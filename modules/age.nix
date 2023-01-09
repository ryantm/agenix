{ config, options, lib, pkgs, ... }:

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

  newGeneration = ''
    _agenix_last_generation=$(basename "$(readlink ${cfg.secretsDir})" || true)
    if [[ $_agenix_last_generation == ${secretsHash} ]]; then
      _agenix_is_current=1
    else
      _agenix_is_current=
    fi
    if [[ ! $_agenix_is_current ]]; then
      _agenix_generation="${secretsHash}"
      echo "[agenix] creating new generation in ${cfg.secretsMountPoint}/$_agenix_generation"
      mkdir -p "${cfg.secretsMountPoint}"
      chmod 0751 "${cfg.secretsMountPoint}"
      grep -q "${cfg.secretsMountPoint} ramfs" /proc/mounts || mount -t ramfs none "${cfg.secretsMountPoint}" -o nodev,nosuid,mode=0751
      mkdir -p "${cfg.secretsMountPoint}/$_agenix_generation"
      chmod 0751 "${cfg.secretsMountPoint}/$_agenix_generation"
    fi
  '';

  identities = builtins.concatStringsSep " " (map (path: "-i ${path}") cfg.identityPaths);

  setTruePath = secretType: ''
    ${if secretType.symlink then ''
      _truePath="${cfg.secretsMountPoint}/$_agenix_generation/${secretType.name}"
    '' else ''
      _truePath="${secretType.path}"
    ''}
  '';

  installSecret = secretType: ''
    ${setTruePath secretType}
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
    mv -f "$TMP_FILE" "$_truePath"

    ${optionalString secretType.symlink ''
      [ "${secretType.path}" != "${cfg.secretsDir}/${secretType.name}" ] && ln -sfn "${cfg.secretsDir}/${secretType.name}" "${secretType.path}"
    ''}
  '';

  testIdentities = map (path: ''
    test -f ${path} || echo '[agenix] WARNING: config.age.identityPaths entry ${path} not present!'
  '') cfg.identityPaths;

  # Add suffix `-incomplete` to the generation when creating some secrets has failed.
  # This ensures that we can try to re-create the generation on subsequent runs.
  renameOnFailure = ''
    if (( _localstatus > 0 )); then
      mv "${cfg.secretsMountPoint}/$_agenix_generation"{,-incomplete}
      _agenix_generation+=-incomplete
    fi
  '';

  cleanupAndLink = ''
    echo "[agenix] symlinking new secrets to ${cfg.secretsDir} (generation $_agenix_generation)..."
    ln -sfn "${cfg.secretsMountPoint}/$_agenix_generation" ${cfg.secretsDir}

    [[ $_agenix_last_generation ]] && {
    echo "[agenix] removing old secrets (generation $_agenix_last_generation)..."
    rm -rf "${cfg.secretsMountPoint}/$_agenix_last_generation"
    }
  '';

  installSecrets = mkInstallScript (
    [ "echo '[agenix] decrypting secrets...'" ]
    ++ testIdentities
    ++ (map installSecret (builtins.attrValues cfg.secrets))
    ++ [ renameOnFailure cleanupAndLink ]
  );

  chownSecret = secretType: ''
    ${setTruePath secretType}
    chown ${secretType.owner}:${secretType.group} "$_truePath"
  '';

  # chown the secrets mountpoint and the current generation to the keys group
  # instead of leaving it root:root.
  chownMountPoint = ''
    chown :keys "${cfg.secretsMountPoint}" "${cfg.secretsMountPoint}/$_agenix_generation"
  '';

  chownSecrets = mkInstallScript (
    [ "echo '[agenix] chowning...'" ]
    ++ [ chownMountPoint ]
    ++ (map chownSecret (builtins.attrValues cfg.secrets)));

  mkInstallScript = strings: ''
    [[ $_agenix_is_current ]] || {
    ${builtins.concatStringsSep "\n" strings}
    }
  '';

  secretsHash = let
    sha256-base16 = builtins.hashString "sha256" (builtins.toJSON cfg.secrets);
  in
    # Truncate to 128 bits to increase readability
    substring 0 32 sha256-base16;

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
        type = mkOptionType {
          name = "nix-path";
          descriptionClass = "noun";
          check = builtins.isPath;
          merge = mergeEqualOption;
        };

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
    system.activationScripts.agenixNewGeneration = {
      text = newGeneration;
      deps = [
        "specialfs"
      ];
    };

    system.activationScripts.agenixInstall = {
      text = installSecrets;
      deps = [
        "agenixNewGeneration"
        "specialfs"
      ];
    };

    # So user passwords can be encrypted.
    system.activationScripts.users.deps = [ "agenixInstall" ];

    # Change ownership and group after users and groups are made.
    system.activationScripts.agenixChown = {
      text = chownSecrets;
      deps = [
        "users"
        "groups"
      ];
    };

    # So other activation scripts can depend on agenix being done.
    system.activationScripts.agenix = {
      text = "";
      deps = [ "agenixChown"];
    };
  };

}
