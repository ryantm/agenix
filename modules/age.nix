{
  config,
  options,
  lib,
  pkgs,
  ...
}:
with lib;
let
  cfg = config.age;

  isDarwin = lib.attrsets.hasAttrByPath [ "environment" "darwinConfig" ] options;

  ageBin = config.age.ageBin;

  users = config.users.users;

  sysusersEnabled =
    if isDarwin then
      false
    else
      options.systemd ? sysusers && (config.systemd.sysusers.enable || config.services.userborn.enable);

  mountCommand =
    if isDarwin then
      ''
        if ! diskutil info "${cfg.secretsMountPoint}" &> /dev/null; then
            num_sectors=1048576
            dev=$(hdiutil attach -nomount ram://"$num_sectors" | sed 's/[[:space:]]*$//')
            newfs_hfs -v agenix "$dev"
            mount -t hfs -o nobrowse,nodev,nosuid,-m=0751 "$dev" "${cfg.secretsMountPoint}"
        fi
      ''
    else
      ''
        grep -q "${cfg.secretsMountPoint} ramfs" /proc/mounts ||
          mount -t ramfs none "${cfg.secretsMountPoint}" -o nodev,nosuid,mode=0751
      '';
  newGeneration = ''
    _agenix_generation="$(basename "$(readlink ${cfg.secretsDir})" || echo 0)"
    (( ++_agenix_generation ))
    echo "[agenix] creating new generation in ${cfg.secretsMountPoint}/$_agenix_generation"
    mkdir -p "${cfg.secretsMountPoint}"
    chmod 0751 "${cfg.secretsMountPoint}"
    ${mountCommand}
    rm -rf -- "${cfg.secretsMountPoint}/$_agenix_generation"
    mkdir -p "${cfg.secretsMountPoint}/$_agenix_generation"
    chmod 0751 "${cfg.secretsMountPoint}/$_agenix_generation"
  '';

  chownGroup = if isDarwin then "admin" else "keys";
  # chown the secrets mountpoint and the current generation to the keys group
  # instead of leaving it root:root.
  chownMountPoint = ''
    chown :${chownGroup} "${cfg.secretsMountPoint}" "${cfg.secretsMountPoint}/$_agenix_generation"
  '';

  setTruePath = secretType: ''
    ${
      if secretType.symlink then
        ''
          _truePath="${cfg.secretsMountPoint}/$_agenix_generation/${secretType.name}"
        ''
      else
        ''
          _truePath="${secretType.path}"
        ''
    }
  '';

  setStagedPath = secretType: ''
    _stagedPath="${cfg.secretsMountPoint}/$_agenix_generation/${secretType.name}"
  '';

  installSecret = secretType: ''
    ${setStagedPath secretType}
    echo "decrypting '${secretType.file}' to '${secretType.path}'..."
    TMP_FILE="$_stagedPath.tmp"

    IDENTITIES=()
    for identity in ${toString cfg.identityPaths}; do
      test -r "$identity" || continue
      test -s "$identity" || continue
      IDENTITIES+=(-i)
      IDENTITIES+=("$identity")
    done

    test "''${#IDENTITIES[@]}" -eq 0 && echo "[agenix] WARNING: no readable identities found!"

    mkdir -p "$(dirname "$_stagedPath")"
    [ "${secretType.path}" != "${cfg.secretsDir}/${secretType.name}" ] && mkdir -p "$(dirname "${secretType.path}")"
    (
      umask u=r,g=,o=
      test -f "${secretType.file}" || echo '[agenix] WARNING: encrypted file ${secretType.file} does not exist!'
      test -d "$(dirname "$TMP_FILE")" || echo "[agenix] WARNING: $(dirname "$TMP_FILE") does not exist!"
      LANG=${
        config.i18n.defaultLocale or "C"
      } ${ageBin} --decrypt "''${IDENTITIES[@]}" -o "$TMP_FILE" "${secretType.file}"
    )
    chmod ${secretType.mode} "$TMP_FILE"
    mv -f "$TMP_FILE" "$_stagedPath"
  '';

  publishSecret = secretType: ''
    ${
      if secretType.symlink then
        optionalString (secretType.path != "${cfg.secretsDir}/${secretType.name}") ''
          ln -sfT "${cfg.secretsDir}/${secretType.name}" "${secretType.path}"
        ''
      else
        ''
          ${setStagedPath secretType}
          _targetTemp="$(mktemp "${secretType.path}.XXXXXX")"
          if ! cp -p -- "$_stagedPath" "$_targetTemp"; then
            rm -f -- "$_targetTemp"
            exit 1
          fi
          if ! mv -f -- "$_targetTemp" "${secretType.path}"; then
            rm -f -- "$_targetTemp"
            exit 1
          fi
          rm -f -- "$_stagedPath"
        ''
    }
  '';

  publishSecrets = builtins.concatStringsSep "\n" (
    map publishSecret (builtins.attrValues cfg.secrets)
  );

  testIdentities = map (path: ''
    test -f ${path} || echo '[agenix] WARNING: config.age.identityPaths entry ${path} not present!'
  '') cfg.identityPaths;

  linkNewGeneration = ''
    echo "[agenix] symlinking new secrets to ${cfg.secretsDir} (generation $_agenix_generation)..."
    ln -sfT "${cfg.secretsMountPoint}/$_agenix_generation" ${cfg.secretsDir}
  '';

  cleanupOldGeneration = ''
    if (( _agenix_generation > 1 )); then
      echo "[agenix] removing old secrets (generation $(( _agenix_generation - 1 )))..."
      rm -rf -- "${cfg.secretsMountPoint}/$(( _agenix_generation - 1 ))"
    fi
  '';

  installSecrets = builtins.concatStringsSep "\n" (
    [ "echo '[agenix] decrypting secrets...'" ]
    ++ testIdentities
    ++ (map installSecret (builtins.attrValues cfg.secrets))
  );

  chownSecret = secretType: ''
    ${setTruePath secretType}
    chown ${secretType.owner}:${secretType.group} "$_truePath"
  '';

  chownSecrets = builtins.concatStringsSep "\n" (
    [ "echo '[agenix] chowning...'" ]
    ++ [ chownMountPoint ]
    ++ (map chownSecret (builtins.attrValues cfg.secrets))
  );

  chownStagedSecrets = builtins.concatStringsSep "\n" (
    [ "echo '[agenix] chowning staged secrets...'" ]
    ++ [ chownMountPoint ]
    ++ (map (secretType: ''
      ${setStagedPath secretType}
      chown ${secretType.owner}:${secretType.group} "$_stagedPath"
    '') (builtins.attrValues cfg.secrets))
  );

  secretType = types.submodule (
    { config, ... }:
    {
      options = {
        name = mkOption {
          type = types.str;
          default = config._module.args.name;
          defaultText = literalExpression "config._module.args.name";
          description = ''
            Name of the file used in {option}`age.secretsDir`
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
          defaultText = literalExpression ''
            "''${cfg.secretsDir}/''${config.name}"
          '';
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
          defaultText = literalExpression ''
            users.''${config.owner}.group or "0"
          '';
          description = ''
            Group of the decrypted secret.
          '';
        };
        symlink = mkEnableOption "symlinking secrets to their destination" // {
          default = true;
        };
      };
    }
  );
in
{
  imports = [
    (mkRenamedOptionModule [ "age" "sshKeyPaths" ] [ "age" "identityPaths" ])
  ];

  options.age = {
    ageBin = mkOption {
      type = types.str;
      default = "${pkgs.age}/bin/age";
      defaultText = literalExpression ''
        "''${pkgs.age}/bin/age"
      '';
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
      type =
        types.addCheck types.str (
          s:
          (builtins.match "[ \t\n]*" s) == null # non-empty
          && (builtins.match ".+/" s) == null
        ) # without trailing slash
        // {
          description = "${types.str.description} (with check: non-empty without trailing slash)";
        };
      default = "/run/agenix.d";
      description = ''
        Where secrets are created before they are symlinked to {option}`age.secretsDir`
      '';
    };
    identityPaths = mkOption {
      type = types.listOf types.path;
      default =
        if isDarwin then
          [
            "/etc/ssh/ssh_host_ed25519_key"
            "/etc/ssh/ssh_host_rsa_key"
          ]
        else if (config.services.openssh.enable or false) then
          map (e: e.path) (
            lib.filter (e: e.type == "rsa" || e.type == "ed25519") config.services.openssh.hostKeys
          )
        else
          [ ];
      defaultText = literalExpression ''
        if isDarwin
        then [
          "/etc/ssh/ssh_host_ed25519_key"
          "/etc/ssh/ssh_host_rsa_key"
        ]
        else if (config.services.openssh.enable or false)
        then map (e: e.path) (lib.filter (e: e.type == "rsa" || e.type == "ed25519") config.services.openssh.hostKeys)
        else [];
      '';
      description = ''
        Path to SSH keys to be used as identities in age decryption.
      '';
    };
  };

  config = mkIf (cfg.secrets != { }) (mkMerge [
    {
      assertions = [
        {
          assertion = cfg.identityPaths != [ ];
          message = "age.identityPaths must be set, for example by enabling openssh.";
        }
      ];
    }
    (optionalAttrs (!isDarwin) {
      # When using sysusers we no longer be started as an activation script
      # because those are started in initrd while sysusers is started later.
      systemd.services.agenix-install-secrets = mkIf sysusersEnabled {
        wantedBy = [ "sysinit.target" ];
        after = [ "systemd-sysusers.service" ];
        unitConfig.DefaultDependencies = "no";

        path = [ pkgs.mount ];
        serviceConfig = {
          Type = "oneshot";
          ExecStart = pkgs.writeShellScript "agenix-install" (concatLines [
            "set -e"
            newGeneration
            installSecrets
            chownStagedSecrets
            publishSecrets
            linkNewGeneration
            cleanupOldGeneration
          ]);
          RemainAfterExit = true;
        };
      };

      # Create a new directory full of secrets for symlinking (this helps
      # ensure removed secrets are actually removed, or at least become
      # invalid symlinks).
      system.activationScripts = mkIf (!sysusersEnabled) {
        agenixNewGeneration = {
          text = newGeneration;
          deps = [
            "specialfs"
          ];
        };

        agenixInstall = {
          text = concatLines [
            installSecrets
            publishSecrets
            linkNewGeneration
          ];
          deps = [
            "agenixNewGeneration"
            "specialfs"
          ];
        };

        # So user passwords can be encrypted.
        users.deps = [ "agenixInstall" ];

        # Change ownership and group after users and groups are made.
        agenixChown = {
          text = concatLines [
            chownSecrets
            cleanupOldGeneration
          ];
          deps = [
            "users"
            "groups"
          ];
        };

        # So other activation scripts can depend on agenix being done.
        agenix = {
          text = "";
          deps = [ "agenixChown" ];
        };
      };
    })

    (optionalAttrs isDarwin {
      launchd.daemons.activate-agenix = {
        script = ''
          set -e
          set -o pipefail
          export PATH="${pkgs.gnugrep}/bin:${pkgs.coreutils}/bin:@out@/sw/bin:/usr/bin:/bin:/usr/sbin:/sbin"
          ${newGeneration}
          ${installSecrets}
          ${chownStagedSecrets}
          ${publishSecrets}
          ${linkNewGeneration}
          ${cleanupOldGeneration}
          exit 0
        '';
        serviceConfig = {
          RunAtLoad = true;
          KeepAlive.SuccessfulExit = false;
        };
      };
    })
  ]);
}
