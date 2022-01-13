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
    [ "${secretType.path}" != "/run/agenix/${secretType.name}" ] && mkdir -p "$(dirname "${secretType.path}")"
    (
      umask u=r,g=,o=
      LANG=${config.i18n.defaultLocale} ${ageBin} --decrypt ${identities} -o "$TMP_FILE" "${secretType.file}"
    )
    chmod ${secretType.mode} "$TMP_FILE"
    chown ${secretType.owner}:${secretType.group} "$TMP_FILE"
    mv -f "$TMP_FILE" "$_truePath"

    ${optionalString secretType.symlink ''
      [ "${secretType.path}" != "/run/agenix/${secretType.name}" ] && ln -sfn "/run/agenix/${secretType.name}" "${secretType.path}"
    ''}
  '';

  isRootSecret = st: (st.owner == "root" || st.owner == "0") && (st.group == "root" || st.group == "0");
  isNotRootSecret = st: !(isRootSecret st);

  rootOwnedSecrets = builtins.filter isRootSecret (builtins.attrValues cfg.secrets);
  installRootOwnedSecrets = builtins.concatStringsSep "\n" ([ "echo '[agenix] decrypting root secrets...'" ] ++ (map installSecret rootOwnedSecrets));

  nonRootSecrets = builtins.filter isNotRootSecret (builtins.attrValues cfg.secrets);
  installNonRootSecrets = builtins.concatStringsSep "\n" ([ "echo '[agenix] decrypting non-root secrets...'" ] ++ (map installSecret nonRootSecrets));

  secretType = types.submodule ({ config, ... }: {
    options = {
      name = mkOption {
        type = types.str;
        default = config._module.args.name;
        description = ''
          Name of the file used in /run/agenix
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
        default = "/run/agenix/${config.name}";
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
      action = mkOption {
        type = types.str;
        default = "";
        description = "A script to run when secret is updated.";
      };
      service = mkOption {
        type = types.str;
        default = "";
        description = "The systemd service that uses this secret. Will be restarted when the secret changes.";
        example = "wireguard-wg0";
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
    secretsMountPoint = mkOption {
      type = types.addCheck types.str
        (s:
          (builtins.match "[ \t\n]*" s) == null # non-empty
            && (builtins.match ".+/" s) == null) # without trailing slash
      // { description = "${types.str.description} (with check: non-empty without trailing slash)"; };
      default = "/run/agenix.d";
      description = ''
        Where secrets are created before they are symlinked to /run/agenix
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
        _agenix_generation="$(basename "$(readlink /run/agenix)" || echo 0)"
        (( ++_agenix_generation ))
        echo "[agenix] symlinking new secrets to /run/agenix (generation $_agenix_generation)..."
        mkdir -p "${cfg.secretsMountPoint}"
        chmod 0751 "${cfg.secretsMountPoint}"
        grep -q "${cfg.secretsMountPoint} ramfs" /proc/mounts || mount -t ramfs none "${cfg.secretsMountPoint}" -o nodev,nosuid,mode=0751
        mkdir -p "${cfg.secretsMountPoint}/$_agenix_generation"
        chmod 0751 "${cfg.secretsMountPoint}/$_agenix_generation"
        ln -sfn "${cfg.secretsMountPoint}/$_agenix_generation" /run/agenix

        (( _agenix_generation > 1 )) && {
          echo "[agenix] removing old secrets (generation $(( _agenix_generation - 1 )))..."
          rm -rf "${cfg.secretsMountPoint}/$(( _agenix_generation - 1 ))"
        }
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
    system.activationScripts.agenix = {
      text = installNonRootSecrets;
      deps = [
        "users"
        "groups"
        "specialfs"
        "agenixMountSecrets"
        "agenixChownKeys"
      ];
    };

    # services that watch for file changes and exectue the configured action
    systemd.services = lib.mkMerge
      (lib.mapAttrsToList
        (name: {action, service, file, path, mode, owner, group, ...}:
          let
            fileHash = builtins.hashFile "sha256" file;
            restartTriggers = [ fileHash path mode owner group ];
          in
            lib.mkMerge [
              (lib.mkIf (service != "") {
                ${service} = { inherit restartTriggers; };
              })
              (lib.mkIf (action != "") {
                "agenix-${name}-action" = {
                  inherit restartTriggers;

                  # We execute the action on reload so that it doesn't happen at
                  # startup. The only disadvantage is that it won't trigger the
                  # first time the service is created.
                  reload = action;
                  reloadIfChanged = true;

                  serviceConfig = {
                    Type = "oneshot";
                    RemainAfterExit = true;
                  };

                  script = " "; # systemd complains if we only set ExecReload

                  # Give it a reason for starting
                  wantedBy = [ "multi-user.target" ];
                };

              })]) cfg.secrets);
  };

}
