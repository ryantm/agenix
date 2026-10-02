{
  config,
  lib,
  pkgs,
  ...
}:
let
  cfg = config.age;
  credentials = lib.filterAttrs (_: credential: credential.enable) cfg.systemdCredentials;
  names = builtins.attrNames credentials;
  directory = "/run/agenix-credentials";
  unit = "agenix-encrypt-credentials";
  validateFile = import ./validated-file.nix {
    inherit lib pkgs;
    enable = cfg.validateSecrets;
  };
  prepare = lib.getExe (
    pkgs.writeShellApplication {
      name = "agenix-encrypt-credentials";
      runtimeInputs = [ pkgs.coreutils ];
      text = ''
          set -euo pipefail
        umask 077
        identities=()
        identity_paths=( ${lib.escapeShellArgs (map toString cfg.identityPaths)} )
        for identity in "''${identity_paths[@]}"; do
            if test -f "$identity" && test -r "$identity" && test -s "$identity"; then
              identities+=(-i "$identity")
            fi
          done
          if test "''${#identities[@]}" -eq 0; then
            echo '[agenix] no readable, non-empty identities for systemd credentials' >&2
            exit 1
          fi
          stage="$(mktemp -d ${directory}/.generation.XXXXXXXX)"
          cleanup() {
            if test -n "$stage"; then rm -rf -- "$stage"; fi
          }
          trap cleanup EXIT
          trap 'exit 130' INT
          trap 'exit 143' TERM
          ${lib.concatMapStringsSep "\n" (name: ''
            ${cfg.ageBin} --decrypt "''${identities[@]}" -- ${
              lib.escapeShellArg (toString (validateFile credentials.${name}.file))
            } |
              ${config.systemd.package}/bin/systemd-creds encrypt \
                --with-key=${lib.escapeShellArg credentials.${name}.withKey} \
                --name=${lib.escapeShellArg name} - "$stage"/${lib.escapeShellArg name}
            chmod 0400 "$stage"/${lib.escapeShellArg name}
          '') names}
          previous="$(readlink ${directory}/current || true)"
          ln -s "$(basename "$stage")" "$stage/.next"
          mv -fT -- "$stage/.next" ${directory}/current
          stage=""
          # Only remove a former generation managed by this service.
          if [[ $previous == .generation.* && $previous != */* ]]; then
            rm -rf -- ${directory}/"$previous"
          fi
      '';
    }
  );
  consumerModules = lib.concatMap (
    name:
    map (service: {
      ${service} = {
        requires = [ "${unit}.service" ];
        after = [ "${unit}.service" ];
        restartTriggers = [ prepare ];
        serviceConfig.LoadCredentialEncrypted = [ "${name}:${credentials.${name}.path}" ];
      };
    }) credentials.${name}.services
  ) names;
in
{
  imports = [ ./age.nix ];
  options.age.systemdCredentials = lib.mkOption {
    default = { };
    description = ''
      Age-encrypted inputs converted to encrypted systemd service credentials
      on the target. Plaintext flows through a pipe, without a shared plaintext
      file. This does not replace normal secrets needed before user creation.
    '';
    type = lib.types.attrsOf (
      lib.types.submodule (
        { name, ... }: {
          options = {
            enable = lib.mkOption {
              type = lib.types.bool;
              default = true;
              description = "Whether to prepare this systemd credential.";
            };
            file = lib.mkOption {
              type = lib.types.path;
              description = "Age-encrypted input file.";
            };
            withKey = lib.mkOption {
              type = lib.types.enum [
                "auto"
                "host"
                "tpm2"
                "host+tpm2"
              ];
              default = "auto";
              description = "Key selection passed to systemd-creds encrypt. Explicit TPM modes fail when unavailable.";
            };
            services = lib.mkOption {
              type = lib.types.listOf lib.types.str;
              default = [ ];
              example = [ "my-service" ];
              description = "NixOS service names, without .service, that receive this credential and depend on its preparation.";
            };
            path = lib.mkOption {
              type = lib.types.str;
              readOnly = true;
              default = "${directory}/current/${name}";
              description = "Path to the encrypted systemd credential, not its plaintext.";
            };
          };
        }
      )
    );
  };
  config = lib.mkIf (names != [ ]) {
    assertions = [
      {
        assertion = cfg.identityPaths != [ ];
        message = "age.systemdCredentials requires age.identityPaths.";
      }
      {
        assertion = builtins.all (
          name: builtins.match "[A-Za-z0-9_][A-Za-z0-9_.-]*" name != null && builtins.stringLength name <= 255
        ) names;
        message = "age.systemdCredentials names must be valid credential filenames of at most 255 bytes.";
      }
      {
        assertion = builtins.all (
          service: service != "" && service != unit && !(lib.hasSuffix ".service" service)
        ) (lib.concatMap (name: credentials.${name}.services) names);
        message = "age.systemdCredentials services must be consumer service names without the .service suffix.";
      }
    ];
    systemd.services = lib.mkMerge (
      [
        {
          ${unit} = {
            description = "Prepare encrypted agenix systemd credentials";
            wantedBy = [ "multi-user.target" ];
            after = [
              "local-fs.target"
              "tpm2.target"
            ];
            unitConfig.RequiresMountsFor =
              cfg.identityPaths ++ map (name: toString credentials.${name}.file) names ++ [ "/var/lib/systemd" ];
            path = [ pkgs.coreutils ];
            serviceConfig = {
              Type = "oneshot";
              RemainAfterExit = true;
              RuntimeDirectory = "agenix-credentials";
              RuntimeDirectoryMode = "0700";
              RuntimeDirectoryPreserve = "yes";
              UMask = "0077";
              ExecStart = prepare;
            };
          };
        }
      ]
      ++ consumerModules
    );
  };
}
