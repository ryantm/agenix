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
    _truePath="${cfg.secretsMountPoint}/$_count/${secretType.name}"
    echo "decrypting '${secretType.file}' to '$_truePath'..."
    TMP_FILE="$_truePath.tmp"
    mkdir -p "$(dirname "$_truePath")"
    mkdir -p "$(dirname "${secretType.path}")"
    (
      umask u=r,g=,o=
      LANG=${config.i18n.defaultLocale} ${ageBin} --decrypt ${identities} -o "$TMP_FILE" "${secretType.file}"
    )
    chmod ${secretType.mode} "$TMP_FILE"
    chown ${secretType.owner}:${secretType.group} "$TMP_FILE"
    mv -f "$TMP_FILE" "$_truePath"
    [ "${secretType.path}" != "/run/secrets/${secretType.name}" ] && ln -sfn "/run/secrets/${secretType.name}" "${secretType.path}"
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
    secretsMountPoint = mkOption {
      type = types.addCheck types.str
        (s:
          (builtins.match "[ \t\n]*" s) == null # non-empty
            && (builtins.match ".+/" s) == null) # without trailing slash
      // { description = "${types.str.description} (with check: non-empty without trailing slash)"; };
      default = "/run/secrets.d";
      description = ''
        Where secrets are created before they are symlinked to /run/secrets
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

  config = mkIf (cfg.secrets != { }) {
    assertions = [{
      assertion = cfg.sshKeyPaths != [ ];
      message = "age.sshKeyPaths must be set.";
    }];

    # Create a new directory full of secrets for symlinking (this helps
    # ensure removed secrets are actually removed, or at least become
    # invalid symlinks).
    system.activationScripts.agenixMountSecrets = ''
      _count="$(basename "$(readlink /run/secrets)" || echo 0)"
      (( ++_count ))
      echo "[agenix] symlinking new secrets to /run/secrets (generation $_count)..."
      mkdir -p "${cfg.secretsMountPoint}"
      chmod 0750 "${cfg.secretsMountPoint}"
      grep -q "${cfg.secretsMountPoint} ramfs" /proc/mounts || mount -t ramfs none "${cfg.secretsMountPoint}" -o nodev,nosuid,mode=0750
      mkdir -p "${cfg.secretsMountPoint}/$_count"
      chmod 0750 "${cfg.secretsMountPoint}/$_count"
      chown :keys "${cfg.secretsMountPoint}" "${cfg.secretsMountPoint}/$_count"
      ln -sfn "${cfg.secretsMountPoint}/$_count" /run/secrets
    '';

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
  };

}
