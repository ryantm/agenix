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

  ageBin = lib.getExe config.age.package;

  isValidSecretName =
    name:
    name != ""
    && !(hasPrefix "/" name)
    && !(hasSuffix "/" name)
    && !(builtins.any (part: part == "" || part == "." || part == "..") (splitString "/" name));

  initDirs = ''
    _agenix_secrets_dir="${cfg.secretsDir}"
    _agenix_secrets_dir="''${_agenix_secrets_dir%/}"
    _agenix_mount_point="${cfg.secretsMountPoint}"
    _agenix_mount_point="''${_agenix_mount_point%/}"
  '';

  currentGeneration = ''
    _agenix_generation=0
    if [[ -L "$_agenix_secrets_dir" ]]; then
      _agenix_target="$(readlink -- "$_agenix_secrets_dir" || true)"
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
    ${optionalString (
      verbosityLevel >= 2
    ) ''echo "[agenix] creating new generation in $_agenix_mount_point/$_agenix_generation"''}
    mkdir -p -- "$_agenix_mount_point"
    chmod -- 0700 "$_agenix_mount_point"
    rm -rf -- "''${_agenix_mount_point:?}/$_agenix_generation"
    mkdir -p -- "$_agenix_mount_point/$_agenix_generation"
    chmod -- 0700 "$_agenix_mount_point/$_agenix_generation"
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

  installSecretHelper = ''
    _agenix_install_secret() {
      local _file="$1" _name="$2" _custom_path="$3" _mode="$4" _symlink="$5"
      local _gen_dir="$_agenix_mount_point/$_agenix_generation"
      local _default_path="$_agenix_secrets_dir/$_name"
      local _path _true_path _tmp_file

      if [[ -n "$_custom_path" ]]; then
        _path="$_custom_path"
      else
        _path="$_default_path"
      fi

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
          umask 0077
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

      _tmp_file="$(mktemp "$_gen_dir/.agenix-tmp.XXXXXXXXXX")"
      if ! (
        umask u=r,g=,o=
        LANG=${
          escapeShellArg (if (config.i18n.defaultLocale or "") != "" then config.i18n.defaultLocale else "C")
        } ${escapeShellArg ageBin} --decrypt "''${_agenix_identities[@]}" -o "$_tmp_file" -- "$_file"
      ); then
        rm -f -- "$_tmp_file"
        return 1
      fi

      if ! chmod -- "$_mode" "$_tmp_file" || ! mv -f -- "$_tmp_file" "$_true_path"; then
        rm -f -- "$_tmp_file"
        return 1
      fi

      if [[ "$_symlink" == 1 && "$_path" != "$_default_path" ]]; then
        ln -sfT -- "$_default_path" "$_path"
      fi
    }
  '';

  installSecretCall =
    secretType:
    let
      isDefaultPath = secretType.path == "${cfg.secretsDir}/${secretType.name}";
      pathArg = if isDefaultPath then "''" else ''"${secretType.path}"'';
    in
    ''
      _agenix_install_secret ${escapeShellArg "${secretType.file}"} ${escapeShellArg secretType.name} ${pathArg} ${escapeShellArg secretType.mode} ${
        if secretType.symlink then "1" else "0"
      }
    '';

  cleanupAndLink = ''
    ${currentGeneration}
    (( ++_agenix_generation ))
    ${optionalString (verbosityLevel >= 2)
      ''echo "[agenix] symlinking new secrets to $_agenix_secrets_dir (generation $_agenix_generation)..."''
    }
    mkdir -p -- "$(dirname -- "$_agenix_secrets_dir")"
    ln -sfT -- "$_agenix_mount_point/$_agenix_generation" "$_agenix_secrets_dir"

    if (( _agenix_generation > 1 )); then
      ${optionalString (
        verbosityLevel >= 2
      ) ''echo "[agenix] removing old secrets (generation $(( _agenix_generation - 1 )))..."''}
      rm -rf -- "''${_agenix_mount_point:?}/$(( _agenix_generation - 1 ))"
    fi
  '';

  enabledSecrets = lib.filter (secret: secret.enable) (builtins.attrValues cfg.secrets);

  installSecrets = builtins.concatStringsSep "\n" (
    (optional (verbosityLevel >= 1) "echo '[agenix] decrypting secrets...'")
    ++ [ probeIdentities ]
    ++ (optionals (enabledSecrets != [ ]) (
      [ installSecretHelper ] ++ (map installSecretCall enabledSecrets)
    ))
    ++ [ cleanupAndLink ]
  );

  secretType = types.submodule (
    {
      config,
      name,
      ...
    }:
    {
      options = {
        enable = mkOption {
          type = types.bool;
          default = true;
          description = "Whether to decrypt and install this secret.";
        };
        name = mkOption {
          type = types.str;
          default = name;
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
        symlink = mkEnableOption "symlinking secrets to their destination" // {
          default = true;
        };
      };
    }
  );

  mountingScript =
    let
      app = pkgs.writeShellApplication {
        name = "agenix-home-manager-mount-secrets";
        runtimeInputs = with pkgs; [ coreutils ];
        text = ''
          ${initDirs}
          ${newGeneration}
          ${installSecrets}
          exit 0
        '';
      };
    in
    lib.getExe app;

  userDirectory =
    dir:
    let
      inherit (pkgs.stdenv.hostPlatform) isDarwin;
      baseDir =
        if isDarwin then "$(${lib.getExe pkgs.getconf} DARWIN_USER_TEMP_DIR)" else "\${XDG_RUNTIME_DIR}";
    in
    "${baseDir}/${dir}";

  userDirectoryDescription =
    dir:
    literalExpression ''
      "''${XDG_RUNTIME_DIR}"/''${dir} on linux or "$(getconf DARWIN_USER_TEMP_DIR)"/''${dir} on darwin.
    '';
in
{
  options.age = {
    enable = mkEnableOption "agenix" // {
      default = enabledSecrets != [ ];
    };

    package = mkPackageOption pkgs "age" { };

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

    identityPaths = mkOption {
      type = types.listOf types.path;
      default = [
        "${config.home.homeDirectory}/.ssh/id_ed25519"
        "${config.home.homeDirectory}/.ssh/id_rsa"
      ];
      defaultText = literalExpression ''
        [
          "''${config.home.homeDirectory}/.ssh/id_ed25519"
          "''${config.home.homeDirectory}/.ssh/id_rsa"
        ]
      '';
      description = ''
        Path to SSH keys to be used as identities in age decryption.
      '';
    };

    secretsDir = mkOption {
      type = types.str;
      default = userDirectory "agenix";
      defaultText = userDirectoryDescription "agenix";
      description = ''
        Folder where secrets are symlinked to
      '';
    };

    secretsMountPoint = mkOption {
      type =
        types.addCheck types.str (
          s: (builtins.match "[ \t\n]*" s) == null && s != "/" && (builtins.match ".+/" s) == null
        )
        // {
          description = "${types.str.description} (with check: non-empty without trailing slash)";
        };
      default = userDirectory "agenix.d";
      defaultText = userDirectoryDescription "agenix.d";
      description = ''
        Where secrets are created before they are symlinked to ''${cfg.secretsDir}
      '';
    };
  };

  config = mkIf cfg.enable {
    assertions = [
      {
        assertion = cfg.identityPaths != [ ];
        message = "age.identityPaths must be set.";
      }
      {
        assertion = !(builtins.any builtins.isPath cfg.identityPaths);
        message = "age.identityPaths must contain path strings (e.g. \"/home/user/.ssh/id_ed25519\"), not Nix path literals, which would copy private keys into the world-readable Nix store.";
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

    systemd.user.services.agenix = lib.mkIf pkgs.stdenv.hostPlatform.isLinux {
      Unit = {
        Description = "agenix activation";
      };
      Service = {
        Type = "oneshot";
        ExecStart = mountingScript;
        RemainAfterExit = true;
      };
      Install.WantedBy = [ "default.target" ];
    };

    launchd.agents.activate-agenix = {
      enable = true;
      config = {
        ProgramArguments = [ mountingScript ];
        KeepAlive = {
          Crashed = false;
          SuccessfulExit = false;
        };
        RunAtLoad = true;
        ProcessType = "Background";
        StandardOutPath = "${config.home.homeDirectory}/Library/Logs/agenix/stdout";
        StandardErrorPath = "${config.home.homeDirectory}/Library/Logs/agenix/stderr";
      };
    };
  };
}
