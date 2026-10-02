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

  newGeneration = ''
    _agenix_generation="$(basename "$(readlink "${cfg.secretsDir}")" || echo 0)"
    (( ++_agenix_generation ))
    ${optionalString (
      verbosityLevel >= 2
    ) ''echo "[agenix] creating new generation in ${cfg.secretsMountPoint}/$_agenix_generation"''}
    mkdir -p "${cfg.secretsMountPoint}"
    chmod 0751 "${cfg.secretsMountPoint}"
    mkdir -p "${cfg.secretsMountPoint}/$_agenix_generation"
    chmod 0751 "${cfg.secretsMountPoint}/$_agenix_generation"
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
    ${optionalString (
      verbosityLevel >= 3
    ) ''echo "decrypting '${secretType.file}' to '$_truePath'..."''}
    TMP_FILE="$_truePath.tmp"

    IDENTITIES=()
    _agenix_identity_paths=( ${toString cfg.identityPaths} )
    for identity in "''${_agenix_identity_paths[@]}"; do
      test -r "$identity" || continue
      IDENTITIES+=(-i)
      IDENTITIES+=("$identity")
    done

    test "''${#IDENTITIES[@]}" -eq 0 && echo "[agenix] WARNING: no readable identities found!" >&2

    mkdir -p "$(dirname "$_truePath")"
    # shellcheck disable=SC2193,SC2050
    [ "${secretType.path}" != "${cfg.secretsDir}/${secretType.name}" ] && mkdir -p "$(dirname "${secretType.path}")"
    (
      umask u=r,g=,o=
      test -f "${secretType.file}" || echo '[agenix] WARNING: encrypted file ${secretType.file} does not exist!' >&2
      test -d "$(dirname "$TMP_FILE")" || echo "[agenix] WARNING: $(dirname "$TMP_FILE") does not exist!" >&2
      LANG=${
        config.i18n.defaultLocale or "C"
      } ${ageBin} --decrypt "''${IDENTITIES[@]}" -o "$TMP_FILE" "${secretType.file}"
    )
    chmod ${secretType.mode} "$TMP_FILE"
    mv -f "$TMP_FILE" "$_truePath"

    ${optionalString secretType.symlink ''
      # shellcheck disable=SC2193,SC2050
      [ "${secretType.path}" != "${cfg.secretsDir}/${secretType.name}" ] && ln -sfT "${cfg.secretsDir}/${secretType.name}" "${secretType.path}"
    ''}
  '';

  testIdentities = map (path: ''
    test -f ${path} || echo '[agenix] WARNING: config.age.identityPaths entry ${path} not present!' >&2
  '') cfg.identityPaths;

  cleanupAndLink = ''
    _agenix_generation="$(basename "$(readlink "${cfg.secretsDir}")" || echo 0)"
    (( ++_agenix_generation ))
    ${optionalString (verbosityLevel >= 2)
      ''echo "[agenix] symlinking new secrets to ${cfg.secretsDir} (generation $_agenix_generation)..."''
    }
    ln -sfT "${cfg.secretsMountPoint}/$_agenix_generation" "${cfg.secretsDir}"

    (( _agenix_generation > 1 )) && {
    ${optionalString (
      verbosityLevel >= 2
    ) ''echo "[agenix] removing old secrets (generation $(( _agenix_generation - 1 )))..."''}
    rm -rf "${cfg.secretsMountPoint}/$(( _agenix_generation - 1 ))"
    }
  '';

  enabledSecrets = lib.filter (secret: secret.enable) (builtins.attrValues cfg.secrets);

  installSecrets = builtins.concatStringsSep "\n" (
    (optional (verbosityLevel >= 1) "echo '[agenix] decrypting secrets...'")
    ++ testIdentities
    ++ (map installSecret enabledSecrets)
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
        This does not affect the agenix command-line tool or other activation output.
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
    ];

    systemd.user.services.agenix = lib.mkIf pkgs.stdenv.hostPlatform.isLinux {
      Unit = {
        Description = "agenix activation";
        After = "basic.target"  # “basic boot-up,” includes impermanence's bind mounts
      };
      Service = {
        Type = "oneshot";
        ExecStart = mountingScript;
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
