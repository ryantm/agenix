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
  verbosityLevel =
    {
      quiet = 0;
      summary = 1;
      progress = 2;
      detailed = 3;
    }
    .${cfg.verbosity};

  isDarwin = lib.attrsets.hasAttrByPath [ "environment" "darwinConfig" ] options;

  ageBin = config.age.ageBin;

  users = config.users.users;
  usersByName = builtins.listToAttrs (
    map (u: nameValuePair u.name u) (filter (u: isString (u.name or null)) (attrValues users))
  );
  defaultGroupForOwner =
    owner:
    if owner == "0" then
      "0"
    else if users ? ${owner} && (users.${owner}.name or null) == owner then
      users.${owner}.group or "0"
    else
      usersByName.${owner}.group or "0";

  defaultLocale = if (config.i18n.defaultLocale or "") != "" then config.i18n.defaultLocale else "C";

  secretsDirStr = toString cfg.secretsDir;
  secretsDirEsc = escapeShellArg secretsDirStr;
  mountPointEsc = escapeShellArg cfg.secretsMountPoint;

  isValidSecretName =
    name:
    name != ""
    && !(hasPrefix "/" name)
    && !(hasSuffix "/" name)
    && !(builtins.any (part: part == "" || part == "." || part == "..") (splitString "/" name));

  sysusersEnabled =
    if isDarwin then
      false
    else
      options.systemd ? sysusers
      && (
        config.systemd.sysusers.enable || (options.services ? userborn && config.services.userborn.enable)
      );

  # Linux /proc/mounts escapes backslash, space, tab, and newline octally.
  procMountsPath =
    replaceStrings [ "\\" " " "\t" "\n" ] [ "\\134" "\\040" "\\011" "\\012" ]
      cfg.secretsMountPoint;
  linuxFsType =
    if lib.versionAtLeast config.boot.kernelPackages.kernel.version "6.4.0" then "tmpfs" else "ramfs";
  linuxMountOpts =
    if linuxFsType == "tmpfs" then "nodev,nosuid,mode=0751,noswap" else "nodev,nosuid,mode=0751";

  mountCommand =
    if isDarwin then
      ''
        if ! diskutil info ${mountPointEsc} &> /dev/null; then
          num_sectors=1048576
          dev=$(hdiutil attach -nomount ram://"$num_sectors" | sed 's/[[:space:]]*$//')
          if ! newfs_hfs -v agenix "$dev" || ! mount -t hfs -o nobrowse,nodev,nosuid,-m=0751 "$dev" ${mountPointEsc}; then
            hdiutil detach "$dev" &> /dev/null || true
            exit 1
          fi
        fi
      ''
    else
      ''
        _agenix_is_mounted=0
        while IFS=' ' read -r _ _agenix_mp _agenix_fstype _; do
          if [[ "$_agenix_mp" == ${escapeShellArg procMountsPath} && ( "$_agenix_fstype" == "tmpfs" || "$_agenix_fstype" == "ramfs" ) ]]; then
            _agenix_is_mounted=1
            break
          fi
        done < /proc/mounts
        if (( ! _agenix_is_mounted )); then
          mount -t ${linuxFsType} none ${mountPointEsc} -o ${linuxMountOpts}
        fi
      '';

  currentGeneration = ''
    _agenix_generation=0
    if [[ -L ${secretsDirEsc} ]]; then
      _agenix_target="$(readlink -- ${secretsDirEsc} || true)"
      _agenix_target="''${_agenix_target%/}"
      _agenix_base="''${_agenix_target##*/}"
      if [[ "$_agenix_base" =~ ^[0-9]+$ ]]; then
        _agenix_generation="$_agenix_base"
      fi
    fi
  '';

  newGeneration = ''
    ${currentGeneration}
    (( ++_agenix_generation ))
    ${optionalString (verbosityLevel >= 2)
      ''echo ${escapeShellArg "[agenix] creating new generation in ${cfg.secretsMountPoint}/"}"$_agenix_generation"''
    }
    mkdir -p -- ${mountPointEsc}
    chmod -- 0751 ${mountPointEsc}
    ${mountCommand}
    chmod -- 0751 ${mountPointEsc}
    rm -rf -- ${mountPointEsc}/"$_agenix_generation"
    mkdir -p -- ${mountPointEsc}/"$_agenix_generation"
    chmod -- 0751 ${mountPointEsc}/"$_agenix_generation"
  '';

  chownGroup = if isDarwin then "admin" else "keys";
  # chown the secrets mountpoint and the current generation to the keys group
  # instead of leaving it root:root.
  chownMountPoint = ''
    chown -- :${escapeShellArg chownGroup} ${mountPointEsc} ${mountPointEsc}/"$_agenix_generation" || _agenix_chown_status=1
  '';

  installSecretHelper = ''
    _agenix_install_secret() {
      local _file="$1" _name="$2" _path="$3" _mode="$4" _symlink="$5"
      local _gen_dir=${mountPointEsc}/"$_agenix_generation"
      local _default_path=${secretsDirEsc}/"$_name"
      local _true_path _tmp_file

      if [[ "$_symlink" == 1 ]]; then
        _true_path="$_gen_dir/$_name"
      else
        _true_path="$_path"
      fi

      ${optionalString (verbosityLevel >= 3) ''
        echo "decrypting '$_file' to '$_true_path'..."
      ''}

      if [[ "$_symlink" == 1 ]]; then
        (
          umask 0026
          mkdir -p -- "$(dirname -- "$_true_path")"
        )
      else
        mkdir -p -- "$(dirname -- "$_true_path")"
      fi
      if [[ "$_path" != "$_default_path" ]]; then
        mkdir -p -- "$(dirname -- "$_path")"
      fi

      if [[ ! -f "$_file" ]]; then
        echo "[agenix] WARNING: encrypted file $_file does not exist!" >&2
      fi

      # Decrypt into a 0600 file inside the root-owned generation directory to
      # prevent symlink attacks when symlink = false targets a non-root directory.
      _tmp_file="$(mktemp "$_gen_dir/.agenix-tmp.XXXXXXXXXX")" || return 1
      if ! (
        umask u=r,g=,o=
        LANG=${escapeShellArg defaultLocale} ${ageBin} --decrypt "''${_agenix_identities[@]}" -o "$_tmp_file" -- "$_file"
      ); then
        rm -f -- "$_tmp_file"
        return 1
      fi

      if ! chmod -- "$_mode" "$_tmp_file" || ! mv -f -- "$_tmp_file" "$_true_path"; then
        rm -f -- "$_tmp_file"
        return 1
      fi

      if [[ "$_symlink" == 1 && "$_path" != "$_default_path" ]]; then
        ln -sfT -- "$_default_path" "$_path" || return 1
      fi
    }
  '';

  installSecretCall = secretType: ''
    _agenix_install_secret ${
      escapeShellArgs [
        "${secretType.file}"
        secretType.name
        secretType.path
        secretType.mode
        (if secretType.symlink then "1" else "0")
      ]
    } || _agenix_install_status=1
  '';

  probeIdentities = ''
    _agenix_identities=()
    for _agenix_identity in ${escapeShellArgs (map toString cfg.identityPaths)}; do
      if [[ ! -f "$_agenix_identity" ]]; then
        echo "[agenix] WARNING: config.age.identityPaths entry $_agenix_identity not present!" >&2
        continue
      fi
      if [[ ! -r "$_agenix_identity" || ! -s "$_agenix_identity" ]]; then
        continue
      fi
      _agenix_identities+=(-i "$_agenix_identity")
    done
    if (( ''${#_agenix_identities[@]} == 0 )); then
      echo "[agenix] WARNING: no readable identities found!" >&2
    fi
  '';

  cleanupAndLink = ''
    ${currentGeneration}
    (( ++_agenix_generation ))
    ${optionalString (verbosityLevel >= 2)
      ''echo ${escapeShellArg "[agenix] symlinking new secrets to ${secretsDirStr} (generation "}"$_agenix_generation)..."''
    }
    mkdir -p -- "$(dirname -- ${secretsDirEsc})"
    ln -sfT -- ${mountPointEsc}/"$_agenix_generation" ${secretsDirEsc}

    if (( _agenix_generation > 1 )); then
      ${optionalString (
        verbosityLevel >= 2
      ) ''echo "[agenix] removing old secrets (generation $(( _agenix_generation - 1 )))..."''}
      rm -rf -- ${mountPointEsc}/"$(( _agenix_generation - 1 ))"
    fi
  '';

  enabledSecrets = lib.filter (secret: secret.enable) (builtins.attrValues cfg.secrets);

  installSecrets = builtins.concatStringsSep "\n" (
    [ "_agenix_install_status=0" ]
    ++ (optional (verbosityLevel >= 1) "echo '[agenix] decrypting secrets...'")
    ++ [ probeIdentities ]
    ++ (optionals (enabledSecrets != [ ]) (
      [ installSecretHelper ] ++ (map installSecretCall enabledSecrets)
    ))
    ++ [
      cleanupAndLink
      "(( _agenix_install_status == 0 ))"
    ]
  );

  chownSecretHelper = ''
    _agenix_chown_secret() {
      local _owner_group="$1" _name="$2" _path="$3" _symlink="$4" _true_path
      if [[ "$_symlink" == 1 ]]; then
        _true_path=${mountPointEsc}/"$_agenix_generation/$_name"
      else
        _true_path="$_path"
      fi
      # Use -h (--no-dereference) so a symlink planted at a symlink=false target
      # can never trick root into chowning an unrelated file.
      chown -h -- "$_owner_group" "$_true_path"
    }
  '';

  chownSecretCall = secretType: ''
    _agenix_chown_secret ${
      escapeShellArgs [
        "${secretType.owner}:${secretType.group}"
        secretType.name
        secretType.path
        (if secretType.symlink then "1" else "0")
      ]
    } || _agenix_chown_status=1
  '';

  chownSecrets = builtins.concatStringsSep "\n" (
    [
      "_agenix_chown_status=0"
      currentGeneration
    ]
    ++ (optional (verbosityLevel >= 2) "echo '[agenix] chowning...'")
    ++ [ chownMountPoint ]
    ++ (optionals (enabledSecrets != [ ]) (
      [ chownSecretHelper ] ++ (map chownSecretCall enabledSecrets)
    ))
    ++ [ "(( _agenix_chown_status == 0 ))" ]
  );

  secretType = types.submodule (
    { config, ... }:
    {
      options = {
        enable = mkOption {
          type = types.bool;
          default = true;
          description = "Whether to decrypt and install this secret.";
        };
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
          default = defaultGroupForOwner config.owner;
          defaultText = literalExpression ''
            (findFirst (u: u.name == config.owner) { } (attrValues users)).group or "0"
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
    enable = mkEnableOption "agenix" // {
      default = enabledSecrets != [ ];
    };

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
    verbosity = mkOption {
      type = types.enum [
        "quiet"
        "summary"
        "progress"
        "detailed"
      ];
      default = "detailed";
      description = ''
        Verbosity of agenix activation messages. "quiet" hides routine messages,
        "summary" prints a summary, "progress" also prints installation steps,
        and "detailed" also prints one line per secret. Warnings and errors are always shown.
        This does not affect the agenix command-line tool or other rebuild output.
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
          && s != "/"
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

  config = mkIf cfg.enable (mkMerge [
    {
      assertions = [
        {
          assertion = cfg.identityPaths != [ ];
          message = "age.identityPaths must be set, for example by enabling openssh.";
        }
        {
          assertion = !(builtins.any builtins.isPath cfg.identityPaths);
          message = "age.identityPaths must contain path strings (e.g. \"/etc/ssh/ssh_host_ed25519_key\"), not Nix path literals, which would copy private keys into the world-readable Nix store.";
        }
        {
          assertion =
            !builtins.isPath cfg.secretsDir
            && secretsDirStr != "/"
            && (builtins.match ".+/" secretsDirStr) == null;
          message = "age.secretsDir must be a non-root string path without a trailing slash.";
        }
        {
          assertion = builtins.all (s: isValidSecretName s.name) enabledSecrets;
          message = "Every enabled age.secrets.<name>.name must be a non-empty relative path without leading/trailing slashes or '.'/'..' components.";
        }
      ];

      warnings =
        optional
          (builtins.any (p: !builtins.isPath p && hasPrefix builtins.storeDir (toString p)) cfg.identityPaths)
          "age.identityPaths contains a path inside ${builtins.storeDir}; private keys in the Nix store are world-readable.";
    }
    (optionalAttrs (!isDarwin) {
      # When using sysusers we can no longer be started as an activation script
      # because those are started in initrd while sysusers is started later.
      systemd.services.agenix-install-secrets = mkIf sysusersEnabled {
        wantedBy = [ "sysinit.target" ];
        # So user passwords can be encrypted.
        before = [
          "systemd-sysusers.service"
          "sysinit.target"
          "shutdown.target"
        ];
        after = [ "systemd-remount-fs.service" ];
        conflicts = [ "shutdown.target" ];
        unitConfig.DefaultDependencies = "no";

        path = [ pkgs.mount ];
        serviceConfig = {
          Type = "oneshot";
          ExecStart = pkgs.writeShellScript "agenix-install" (concatLines [
            newGeneration
            installSecrets
          ]);
          RemainAfterExit = true;
        };
      };

      systemd.services.agenix-chown = mkIf sysusersEnabled {
        wantedBy = [ "sysinit.target" ];
        # Change ownership and group after users and groups are made.
        # (And after secrets are created, just in case systemd-sysusers.service is disabled.)
        after = [
          "systemd-sysusers.service"
          "agenix-install-secrets.service"
        ];
        before = [
          "sysinit.target"
          "shutdown.target"
        ];
        conflicts = [ "shutdown.target" ];
        # Restart when agenix-install-secrets is restarted (to chown the new generation).
        requires = [ "agenix-install-secrets.service" ];
        partOf = [ "agenix-install-secrets.service" ];
        restartTriggers = [
          config.systemd.services.agenix-install-secrets.serviceConfig.ExecStart
        ];
        unitConfig.DefaultDependencies = "no";

        serviceConfig = {
          Type = "oneshot";
          ExecStart = pkgs.writeShellScript "agenix-chown" chownSecrets;
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
          text = installSecrets;
          deps = [
            "agenixNewGeneration"
            "specialfs"
          ];
        };

        # So user passwords can be encrypted.
        users.deps = [ "agenixInstall" ];

        # Change ownership and group after users and groups are made.
        agenixChown = {
          text = chownSecrets;
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
          export PATH="${pkgs.coreutils}/bin:@out@/sw/bin:/usr/bin:/bin:/usr/sbin:/sbin"
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
