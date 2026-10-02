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
  shared = import ./secret-install.nix { inherit lib; };
  installer = shared.installer {
    inherit cfg mountCommand;
    validateFile = import ./validated-file.nix {
      inherit lib pkgs;
      enable = cfg.validateSecrets;
    };
    ageBin = config.age.ageBin;
    locale = config.i18n.defaultLocale or "C";
  };
  inherit (installer) currentGeneration enabledSecrets setTruePath;
  verbosityLevel = shared.verbosityLevels.${cfg.verbosity};

  isDarwin = lib.attrsets.hasAttrByPath [ "environment" "darwinConfig" ] options;

  users = config.users.users;

  sysusersEnabled =
    if isDarwin then
      false
    else
      options.systemd ? sysusers
      && (
        config.systemd.sysusers.enable || (options.services ? userborn && config.services.userborn.enable)
      );

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
  chownGroup = if isDarwin then "admin" else "keys";
  # chown the secrets mountpoint and the current generation to the keys group
  # instead of leaving it root:root.
  chownMountPoint = ''
    chown :${chownGroup} "${cfg.secretsMountPoint}" "${cfg.secretsMountPoint}/$_agenix_generation"
  '';

  chownSecret = secretType: ''
    ${setTruePath secretType}
    chown ${secretType.owner}:${secretType.group} "$_truePath"
  '';

  chownSecrets = builtins.concatStringsSep "\n" (
    (optional (verbosityLevel >= 2) "echo '[agenix] chowning...'")
    ++ [ chownMountPoint ]
    ++ (map chownSecret enabledSecrets)
  );

  secretType = types.submodule (
    { config, name, ... }:
    {
      options =
        shared.secretOptions {
          inherit config name;
          secretsDir = cfg.secretsDir;
          nameDefaultText = literalExpression "config._module.args.name";
          pathDefaultText = literalExpression ''
            "''${cfg.secretsDir}/''${config.name}"
          '';
        }
        // {
          owner = mkOption {
            type = types.str;
            default = "0";
            description = "User of the decrypted secret.";
          };
          group = mkOption {
            type = types.str;
            default = (findFirst (u: u.name == config.owner) { } (attrValues users)).group or "0";
            defaultText = literalExpression ''
              (findFirst (u: u.name == config.owner) { } (attrValues users)).group or "0"
            '';
            description = "Group of the decrypted secret.";
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
    verbosity = shared.verbosityOption "other rebuild output";

    validateSecrets = shared.validationOption;

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

  config = mkIf cfg.enable (mkMerge [
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
        # So user passwords can be encrypted.
        before = [ "systemd-sysusers.service" ];
        unitConfig.DefaultDependencies = "no";

        path = [ pkgs.mount ];
        serviceConfig = {
          Type = "oneshot";
          ExecStart = pkgs.writeShellScript "agenix-install" (concatLines [
            installer.newGeneration
            installer.installSecrets
            # Don't fail the systemd unit if our script ended with a failing test.
            "true"
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
        # We should get restarted when agenix-install-secrets is (to chown the new secrets).
        requires = [ "agenix-install-secrets.service" ];
        unitConfig.DefaultDependencies = "no";

        serviceConfig = {
          Type = "oneshot";
          ExecStart = pkgs.writeShellScript "agenix-chown" (concatLines [
            currentGeneration
            chownSecrets
            # Don't fail the systemd unit if our script ended with a failing test.
            "true"
          ]);
          RemainAfterExit = true;
        };
      };

      # Create a new directory full of secrets for symlinking (this helps
      # ensure removed secrets are actually removed, or at least become
      # invalid symlinks).
      system.activationScripts = mkIf (!sysusersEnabled) {
        agenixNewGeneration = {
          text = installer.newGeneration;
          deps = [
            "specialfs"
          ];
        };

        agenixInstall = {
          text = installer.installSecrets;
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
          export PATH="${pkgs.gnugrep}/bin:${pkgs.coreutils}/bin:@out@/sw/bin:/usr/bin:/bin:/usr/sbin:/sbin"
          ${installer.newGeneration}
          ${installer.installSecrets}
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
