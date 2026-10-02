# Standalone Hjem consumes a manifest and packages, rather than NixOS modules.
{
  pkgs,
  homeDirectory,
  configHome ? "${homeDirectory}/.config",
  stateHome ? "${homeDirectory}/.local/state",
  modules ? [ ],
  specialArgs ? { },
}:
let
  inherit (pkgs) lib;
  shared = import ../modules/secret-install.nix { inherit lib; };
  evaluated = lib.evalModules {
    specialArgs = specialArgs // {
      inherit pkgs;
    };
    modules = [
      (
        { config, ... }:
        let
          ageConfig = config.age;
        in
        {
          options.age = {
            enable = lib.mkEnableOption "agenix" // {
              default = lib.any (secret: secret.enable) (builtins.attrValues config.age.secrets);
            };
            package = lib.mkPackageOption pkgs "age" { };
            verbosity = shared.verbosityOption "Hjem output";
            validateSecrets = shared.validationOption;
            identityPaths = lib.mkOption {
              type = lib.types.listOf lib.types.path;
              default = [
                "${homeDirectory}/.ssh/id_ed25519"
                "${homeDirectory}/.ssh/id_rsa"
              ];
              description = "Private identity files available during user service startup.";
            };
            secretsDir = lib.mkOption {
              type = lib.types.str;
              default = "${stateHome}/agenix";
              description = "Stable symlink exposing the current secret generation.";
            };
            secretsMountPoint = lib.mkOption {
              type = lib.types.str;
              default = "\${XDG_RUNTIME_DIR}/agenix.d";
              description = "Runtime directory containing decrypted generations.";
            };
            secrets = lib.mkOption {
              default = { };
              type = lib.types.attrsOf (
                lib.types.submodule (
                  { config, name, ... }:
                  {
                    options = shared.secretOptions {
                      inherit config name;
                      secretsDir = ageConfig.secretsDir;
                    };
                  }
                )
              );
              description = "Encrypted files to install for the current user.";
            };
          };
        }
      )
    ]
    ++ modules;
  };
  cfg = evaluated.config.age;
  installer = shared.installer {
    inherit cfg;
    ageBin = lib.getExe cfg.package;
    locale = "C";
    validateFile = import ../modules/validated-file.nix {
      inherit lib pkgs;
      enable = cfg.validateSecrets;
    };
  };
  decrypt = pkgs.writeShellApplication {
    name = "agenix-hjem-decrypt";
    runtimeInputs = [ pkgs.coreutils ];
    text = ''
      : "''${XDG_RUNTIME_DIR:?agenix requires a user runtime directory}"
      ${installer.prepareIdentities}
      ${installer.newGeneration}
      ${installer.installSecrets}
      exit 0
    '';
  };
  unit = pkgs.writeTextFile {
    name = "agenix-hjem-service";
    destination = "/lib/systemd/user/agenix.service";
    text = ''
      [Unit]
      Description=agenix user secrets

      [Service]
      Type=oneshot
      RemainAfterExit=yes
      ExecStart=${lib.getExe decrypt}

      [Install]
      WantedBy=default.target
    '';
  };
  activate = pkgs.writeShellApplication {
    name = "agenix-hjem-activate";
    runtimeInputs = [ pkgs.systemd ];
    text = ''
      systemctl --user daemon-reload
      systemctl --user restart agenix.service
    '';
  };
  package = pkgs.symlinkJoin {
    name = "agenix-hjem";
    paths = [
      activate
      unit
    ];
  };
in
assert lib.assertMsg pkgs.stdenv.hostPlatform.isLinux
  "agenix.lib.hjemConfiguration currently requires Linux with a systemd user manager.";
assert lib.assertMsg (
  lib.hasPrefix "/" homeDirectory && lib.hasPrefix "/" configHome && lib.hasPrefix "/" stateHome
) "agenix.lib.hjemConfiguration requires absolute homeDirectory, configHome, and stateHome paths.";
assert lib.assertMsg (!cfg.enable || cfg.identityPaths != [ ]) "age.identityPaths must be set.";
{
  paths = lib.mapAttrs (_: secret: secret.path) cfg.secrets;
  manifest = {
    version = 3;
    files = lib.optionals cfg.enable [
      {
        type = "symlink";
        source = "${package}/lib/systemd/user/agenix.service";
        target = "${configHome}/systemd/user/agenix.service";
      }
      {
        type = "symlink";
        source = "${package}/lib/systemd/user/agenix.service";
        target = "${configHome}/systemd/user/default.target.wants/agenix.service";
      }
    ];
  };
  packages = lib.optionals cfg.enable [ package ];
}
