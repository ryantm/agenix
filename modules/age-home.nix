{
  config,
  options,
  lib,
  pkgs,
  ...
}:
with lib; let
  cfg = config.age;

  ageBin = lib.getExe config.age.package;

  newGeneration = ''
    _agenix_generation="$(basename "$(readlink "${cfg.secretsDir}")" || echo 0)"
    (( ++_agenix_generation ))
    echo "[agenix] creating new generation in ${cfg.secretsMountPoint}/$_agenix_generation"
    mkdir -p "${cfg.secretsMountPoint}"
    chmod 0751 "${cfg.secretsMountPoint}"
    mkdir -p "${cfg.secretsMountPoint}/$_agenix_generation"
    chmod 0751 "${cfg.secretsMountPoint}/$_agenix_generation"
  '';

  setTruePath = secretType: ''
    ${
      if secretType.symlink
      then ''
        _truePath="${cfg.secretsMountPoint}/$_agenix_generation/${secretType.name}"
      ''
      else ''
        _truePath="${secretType.path}"
      ''
    }
  '';

  installSecret = secretType: ''
    ${setTruePath secretType}
    echo "decrypting '${secretType.file}' to '$_truePath'..."
    TMP_FILE="$_truePath.tmp"

    IDENTITIES=()
    # shellcheck disable=2043
    for identity in ${toString cfg.identityPaths}; do
      test -r "$identity" || continue
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
      LANG=${config.i18n.defaultLocale or "C"} ${ageBin} --decrypt "''${IDENTITIES[@]}" -o "$TMP_FILE" "${secretType.file}"
    )
    chmod ${secretType.mode} "$TMP_FILE"
    mv -f "$TMP_FILE" "$_truePath"

    ${optionalString secretType.symlink ''
      [ "${secretType.path}" != "${cfg.secretsDir}/${secretType.name}" ] && ln -sfn "${cfg.secretsDir}/${secretType.name}" "${secretType.path}"
    ''}
  '';

  testIdentities =
    map
    (path: ''
      test -f ${path} || echo '[agenix] WARNING: config.age.identityPaths entry ${path} not present!'
    '')
    cfg.identityPaths;

  cleanupAndLink = ''
    _agenix_generation="$(basename "$(readlink "${cfg.secretsDir}")" || echo 0)"
    (( ++_agenix_generation ))
    echo "[agenix] symlinking new secrets to ${cfg.secretsDir} (generation $_agenix_generation)..."
    ln -sfn "${cfg.secretsMountPoint}/$_agenix_generation" "${cfg.secretsDir}"

    (( _agenix_generation > 1 )) && {
    echo "[agenix] removing old secrets (generation $(( _agenix_generation - 1 )))..."
    rm -rf "${cfg.secretsMountPoint}/$(( _agenix_generation - 1 ))"
    }
  '';

  installSecrets = builtins.concatStringsSep "\n" (
    ["echo '[agenix] decrypting secrets...'"]
    ++ testIdentities
    ++ (map installSecret (builtins.attrValues cfg.secrets))
    ++ [cleanupAndLink]
  );

  secretType = types.submodule ({
    config,
    name,
    ...
  }: {
    options = {
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
      symlink = mkEnableOption "symlinking secrets to their destination" // {default = true;};
    };
  });

  mountingScript = let
    app = pkgs.writeShellApplication {
      name = "agenix-home-manager-mount-secrets";
      runtimeInputs = with pkgs; [coreutils];
      text = ''
        ${newGeneration}
        ${installSecrets}
        exit 0
      '';
    };
  in
    lib.getExe app;

  userDirectory = dir: let
    inherit (pkgs.stdenv.hostPlatform) isDarwin;
    baseDir =
      if isDarwin
      then "$(getconf DARWIN_USER_TEMP_DIR)"
      else "$XDG_RUNTIME_DIR";
  in "${baseDir}/${dir}";

  userDirectoryDescription = dir: ''
    "$XDG_RUNTIME_DIR"/${dir} on linux or "$(getconf DARWIN_USER_TEMP_DIR)"/${dir} on darwin.
  '';
in {
  options.age = {
    package = mkPackageOption pkgs "rage" {};

    secrets = mkOption {
      type = types.attrsOf secretType;
      default = {};
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
      defaultText = litteralExpression ''
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

  config = mkIf (cfg.secrets != {}) {
    assertions = [
      {
        assertion = cfg.identityPaths != [];
        message = "age.identityPaths must be set.";
      }
    ];

    systemd.user.services.agenix = lib.mkIf pkgs.stdenv.hostPlatform.isLinux {
      Unit = {
        Description = "agenix activation";
      };
      Service = {
        Type = "oneshot";
        ExecStart = mountingScript;
      };
      Install.WantedBy = ["default.target"];
    };

    launchd.agents.activate-agenix = {
      enable = true;
      config = {
        ProgramArguments = [mountingScript];
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
