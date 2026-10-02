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
  defaultSecretsDir = "${config.xdg.stateHome}/agenix";
  shared = import ./secret-install.nix { inherit lib; };
  installer = shared.installer {
    inherit cfg;
    ageBin = lib.getExe config.age.package;
    locale = config.i18n.defaultLocale or "C";
  };
  inherit (installer) enabledSecrets;
  secretType = types.submodule (
    { config, name, ... }:
    {
      options = shared.secretOptions {
        inherit config name;
        secretsDir = cfg.secretsDir;
      };
    }
  );

  mountingScript =
    let
      app = pkgs.writeShellApplication {
        name = "agenix-home-manager-mount-secrets";
        runtimeInputs = with pkgs; [ coreutils ];
        text = ''
          ${optionalString (cfg.secretsDir == defaultSecretsDir) ''
            # Preserve generation numbering when migrating the previous default.
            # The next installation then removes that old generation normally.
            if [ ! -e "${cfg.secretsDir}" ] && [ ! -L "${cfg.secretsDir}" ] &&
               [ -L "${userDirectory "agenix"}" ]; then
              mkdir -p "$(dirname "${cfg.secretsDir}")"
              mv -T -- "${userDirectory "agenix"}" "${cfg.secretsDir}"
            fi
          ''}
          ${installer.newGeneration}
          ${installer.installSecrets}
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

    verbosity = shared.verbosityOption "other activation output";

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
      default = defaultSecretsDir;
      defaultText = literalExpression ''"''${config.xdg.stateHome}/agenix"'';
      description = ''
        Stable path exposing the current generation. Secret generations remain
        in age.secretsMountPoint; this path is a symlink to the current one.
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
