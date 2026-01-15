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

  # Whether to decrypt during activation (vs only via systemd)
  # When sysusers is enabled, we MUST use systemd-only mode because activation
  # scripts run before sysusers creates users/groups.
  decryptDuringActivation = cfg.installationMode == "activation" && !sysusersEnabled;

  # Collect all paths that need to be mounted for RequiresMountsFor
  # Includes: secretsDir, secretsMountPoint, identityPaths, AND all custom secret destination paths
  secretMountPaths = lib.unique (
    [
      cfg.secretsDir
      cfg.secretsMountPoint
    ]
    ++ cfg.identityPaths
    ++ map (s: s.path) (builtins.attrValues cfg.secrets)
  );

  # Check if any user's hashedPasswordFile references an agenix secret
  # Use toString for robust path comparison (handles both path and string types)
  agenixSecretPaths = map (s: toString s.path) (builtins.attrValues cfg.secrets);
  # Use filterAttrs to preserve user names for error messages
  usersWithAgenixPasswords =
    if isDarwin then
      { }
    else
      lib.filterAttrs (
        name: u:
        (u.hashedPasswordFile or null) != null
        && builtins.elem (toString u.hashedPasswordFile) agenixSecretPaths
      ) config.users.users;

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

  installSecret = secretType: ''
    ${setTruePath secretType}
    echo "decrypting '${secretType.file}' to '$_truePath'..."
    TMP_FILE="$_truePath.tmp"

    IDENTITIES=()
    for identity in ${toString cfg.identityPaths}; do
      test -r "$identity" || continue
      test -s "$identity" || continue
      IDENTITIES+=(-i)
      IDENTITIES+=("$identity")
    done

    test "''${#IDENTITIES[@]}" -eq 0 && echo "[agenix] WARNING: no readable identities found!"

    mkdir -p "$(dirname "$_truePath")"
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
    mv -f "$TMP_FILE" "$_truePath"

    ${optionalString secretType.symlink ''
      [ "${secretType.path}" != "${cfg.secretsDir}/${secretType.name}" ] && ln -sfT "${cfg.secretsDir}/${secretType.name}" "${secretType.path}"
    ''}
  '';

  testIdentities = map (path: ''
    test -f ${path} || echo '[agenix] WARNING: config.age.identityPaths entry ${path} not present!'
  '') cfg.identityPaths;

  cleanupAndLink = ''
    _agenix_generation="$(basename "$(readlink ${cfg.secretsDir})" || echo 0)"
    (( ++_agenix_generation ))
    echo "[agenix] symlinking new secrets to ${cfg.secretsDir} (generation $_agenix_generation)..."
    ln -sfT "${cfg.secretsMountPoint}/$_agenix_generation" ${cfg.secretsDir}

    (( _agenix_generation > 1 )) && {
    echo "[agenix] removing old secrets (generation $(( _agenix_generation - 1 )))..."
    rm -rf "${cfg.secretsMountPoint}/$(( _agenix_generation - 1 ))"
    }
  '';

  installSecrets = builtins.concatStringsSep "\n" (
    [ "echo '[agenix] decrypting secrets...'" ]
    ++ testIdentities
    ++ (map installSecret (builtins.attrValues cfg.secrets))
    ++ [ cleanupAndLink ]
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

  # Generate barrier verification script that checks ALL secrets exist
  # Use escapeShellArg for safety with special characters in names/paths
  barrierChecks = builtins.concatStringsSep "\n" (
    map (secret: ''
      if ! [ -r ${lib.escapeShellArg secret.path} ]; then
        echo "[agenix] ERROR: secret ${lib.escapeShellArg secret.name} not found or not readable at ${lib.escapeShellArg secret.path}" >&2
        _missing=1
      fi
    '') (builtins.attrValues cfg.secrets)
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
    installationMode = mkOption {
      type = types.enum [
        "activation"
        "systemd"
      ];
      default = "activation";
      description = ''
        Controls when secrets are decrypted:

        - `"activation"` (default): Secrets are decrypted during NixOS system
          activation. This is required for {option}`users.users.<name>.hashedPasswordFile`
          and other activation-time features that depend on secrets.
          A systemd service (`agenix-install-secrets.service`) is also created
          as a barrier/marker that other services can depend on for ordering.

        - `"systemd"`: Secrets are ONLY decrypted by the systemd service, not
          during activation. Use this when your decryption key is not available
          until a systemd service runs (e.g., key on a USB drive that needs to
          be mounted first).

          **Warning**: This mode is INCOMPATIBLE with
          {option}`users.users.<name>.hashedPasswordFile` since user creation
          happens before systemd services run. An assertion will fail if you
          try to use both.

          To add dependencies for the decryption key:
          ```nix
          systemd.services.agenix-install-secrets = {
            requires = [ "mnt-usb.mount" ];
            after = [ "mnt-usb.mount" ];
          };
          ```

        Note: When {option}`systemd.sysusers.enable` or {option}`services.userborn.enable`
        is active, you MUST use `"systemd"` mode because activation scripts run
        before sysusers creates users.

        This option only affects Linux systems; Darwin always uses launchd.
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
        {
          # Hard assertion: cannot use hashedPasswordFile with systemd-only mode
          assertion = isDarwin || decryptDuringActivation || usersWithAgenixPasswords == { };
          message = ''
            agenix: Cannot use age.installationMode = "systemd" with users.users.<name>.hashedPasswordFile.

            The following users have hashedPasswordFile pointing to agenix secrets:
            ${builtins.concatStringsSep "\n" (
              lib.mapAttrsToList (
                name: u: "  - ${name}: ${toString u.hashedPasswordFile}"
              ) usersWithAgenixPasswords
            )}

            User passwords must be set during NixOS activation, before systemd services run.
            With installationMode = "systemd", secrets are not available during activation.

            Either:
            1. Set age.installationMode = "activation" (default), or
            2. Use a different mechanism for user passwords (e.g., passwordFile with a non-agenix path)
          '';
        }
        {
          # When sysusers is enabled, activation-time decryption doesn't work
          # because activation scripts run before sysusers creates users
          assertion = isDarwin || !sysusersEnabled || cfg.installationMode == "systemd";
          message = ''
            agenix: systemd.sysusers.enable or services.userborn.enable is active, but
            age.installationMode is set to "activation".

            When sysusers/userborn is enabled, user creation happens via systemd after
            activation scripts complete. This means activation-time secret decryption
            cannot set proper ownership because users don't exist yet.

            Please set:
              age.installationMode = "systemd";

            Note: This means hashedPasswordFile will not work with agenix secrets.
          '';
        }
      ];

      warnings = optional (!isDarwin && !decryptDuringActivation) ''
        agenix: installationMode is set to "systemd". Secrets will NOT be
        available during NixOS activation.

        - Systemd services can depend on agenix-install-secrets.service
        - User passwords (hashedPasswordFile) cannot use agenix secrets
        - Activation scripts cannot depend on secrets

        Add custom dependencies for the decryption key:
          systemd.services.agenix-install-secrets.requires = [ "mnt-usb.mount" ];
          systemd.services.agenix-install-secrets.after = [ "mnt-usb.mount" ];
      '';
    }
    (optionalAttrs (!isDarwin) {
      # Systemd service for secret installation.
      # Behavior depends on installationMode:
      # - "activation" (and !sysusers): This is a BARRIER unit that starts after
      #   NixOS activation completes. Secrets are decrypted by activation scripts.
      #   Other services can depend on this unit for ordering.
      # - "systemd" (or sysusers): This unit performs the actual decryption.
      #   Use this when decryption keys require external resources (USB, network).
      systemd.services.agenix-install-secrets = {
        description =
          if decryptDuringActivation then
            "Agenix secrets barrier (secrets decrypted during activation)"
          else
            "Decrypt agenix secrets";

        wantedBy = [ "multi-user.target" ];

        # Ordering dependencies
        after =
          if decryptDuringActivation then
            # Barrier mode: start after NixOS activation is complete
            # (secrets are already available from activation scripts)
            [ "nixos-activation.service" ]
          else
            # Decryption mode: wait for filesystems and user creation
            # nixos-activation.service ensures users/groups exist for chown
            [
              "local-fs.target"
              "nixos-activation.service"
            ]
            ++ optionals (options.systemd ? sysusers && config.systemd.sysusers.enable) [
              "systemd-sysusers.service"
            ]
            ++ optionals (config.services ? userborn && config.services.userborn.enable) [ "userborn.service" ];

        # Ensure all paths we need are mounted (in decryption mode)
        unitConfig = mkIf (!decryptDuringActivation) {
          # RequiresMountsFor ensures the unit waits for these paths to be available
          RequiresMountsFor = secretMountPaths;
        };

        serviceConfig = mkMerge [
          {
            Type = "oneshot";
            ExecStart = lib.getExe (
              if decryptDuringActivation then
                # Barrier mode: verify ALL secrets exist and are readable
                pkgs.writeShellApplication {
                  name = "agenix-barrier";
                  runtimeInputs = with pkgs; [
                    coreutils
                    gnugrep
                    mount
                  ];
                  text = ''
                    set -uo pipefail
                    _missing=0
                    _secretsDir=${lib.escapeShellArg cfg.secretsDir}

                    # Check that secretsDir symlink exists and resolves
                    if ! [ -L "$_secretsDir" ] || ! [ -d "$_secretsDir" ]; then
                      echo "[agenix] ERROR: secrets directory not found at $_secretsDir" >&2
                      echo "[agenix] This indicates activation scripts failed to decrypt secrets." >&2
                      exit 1
                    fi

                    # Verify each expected secret exists and is readable
                    ${barrierChecks}

                    if [ "$_missing" -ne 0 ]; then
                      echo "[agenix] ERROR: one or more secrets are missing or unreadable" >&2
                      exit 1
                    fi

                    echo "[agenix] all secrets available (decrypted during activation)"
                  '';
                }
              else
                # Decryption mode: perform actual decryption
                pkgs.writeShellApplication {
                  name = "agenix-install";
                  runtimeInputs = with pkgs; [
                    coreutils
                    gnugrep
                    mount
                  ];
                  excludeShellChecks = [ "2050" ];
                  text = ''
                    set -euo pipefail
                    ${newGeneration}
                    ${installSecrets}
                    ${chownSecrets}
                  '';
                }
            );
            RemainAfterExit = true;
          }
          # Add retry logic for systemd decryption mode
          (mkIf (!decryptDuringActivation) {
            Restart = "on-failure";
            RestartSec = "2s";
          })
        ];
      };

      # Activation scripts for secret decryption.
      # Only defined when decryptDuringActivation is true.
      # When using systemd-only mode, NO activation scripts are created
      # (to avoid false confidence that secrets exist during activation).
      system.activationScripts = mkIf decryptDuringActivation {
        agenixNewGeneration = {
          text = newGeneration;
          deps = [ "specialfs" ];
        };

        agenixInstall = {
          text = installSecrets;
          deps = [
            "agenixNewGeneration"
            "specialfs"
          ];
        };

        # So user passwords can be set from secrets.
        users.deps = [ "agenixInstall" ];

        # Change ownership and group after users and groups are made.
        agenixChown = {
          text = chownSecrets;
          deps = [
            "users"
            "groups"
          ];
        };

        # Marker so other activation scripts can depend on agenix being done.
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
          ${chownSecrets}
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
