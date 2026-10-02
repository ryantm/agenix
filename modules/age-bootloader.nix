{
  config,
  lib,
  pkgs,
  ...
}:
let
  cfg = config.age;
  secrets = lib.filterAttrs (_: secret: secret.enable) cfg.bootloaderSecrets;
  names = builtins.attrNames secrets;
  directory = "/run/agenix-bootloader";
  validateFile = import ./validated-file.nix {
    inherit lib pkgs;
    enable = cfg.validateSecrets;
  };
  prepare = lib.concatMapStringsSep "\n" (name: ''
    ${cfg.ageBin} --decrypt "''${identities[@]}" \
      --output "$stage"/${lib.escapeShellArg name} ${
        lib.escapeShellArg (toString (validateFile secrets.${name}.file))
      }
    chmod 0400 "$stage"/${lib.escapeShellArg name}
  '') names;
  publish = lib.concatMapStringsSep "\n" (name: ''
    mv -fT -- "$stage"/${lib.escapeShellArg name} ${lib.escapeShellArg secrets.${name}.path}
    published+=(${lib.escapeShellArg secrets.${name}.path})
  '') names;
  wrap =
    command:
    pkgs.writeShellScript "agenix-install-bootloader" ''
      set -euo pipefail
      export PATH=${
        lib.makeBinPath [
          pkgs.coreutils
          pkgs.util-linux
        ]
      }:"$PATH"
      umask 077
      # Serialize direct invocations as well as switch-to-configuration calls.
      exec 9>${directory}.lock
      flock 9
      if test -L ${directory} || { test -e ${directory} && ! test -d ${directory}; }; then
        echo '[agenix] bootloader secret directory is not a regular directory' >&2
        exit 1
      fi
      mkdir -p ${directory}
      chown 0:0 ${directory}
      chmod 0700 ${directory}
      identities=()
      for identity in ${lib.escapeShellArgs (map toString cfg.identityPaths)}; do
        if test -f "$identity" && test -r "$identity" && test -s "$identity"; then
          identities+=(-i "$identity")
        fi
      done
      if test "''${#identities[@]}" -eq 0; then
        echo '[agenix] no readable, non-empty identities for bootloader secrets' >&2
        exit 1
      fi
      stage="$(mktemp -d ${directory}/.stage.XXXXXXXX)"
      published=()
      cleanup() {
        status=$?
        trap - EXIT
        rm -f -- "''${published[@]}"
        rm -rf -- "$stage"
        exit "$status"
      }
      trap cleanup EXIT
      trap 'exit 130' INT
      trap 'exit 143' TERM
      ${prepare}
      ${publish}
      ${command} "$@"
    '';
in
{
  imports = [ ./age.nix ];

  options.age.bootloaderSecrets = lib.mkOption {
    default = { };
    description = ''
      Root-only secrets decrypted immediately before bootloader installation.
      Plaintext prepared by the wrapper is removed when the installer returns.
      These secrets are independent of normal activation and user creation.
    '';
    type = lib.types.attrsOf (
      lib.types.submodule (
        { name, ... }:
        {
          options = {
            enable = lib.mkOption {
              type = lib.types.bool;
              default = true;
              description = "Whether to prepare this bootloader secret.";
            };
            file = lib.mkOption {
              type = lib.types.path;
              description = "Age-encrypted input file.";
            };
            path = lib.mkOption {
              type = lib.types.str;
              readOnly = true;
              default = "${directory}/${name}";
              description = "Root-only plaintext path available during bootloader installation.";
            };
          };
        }
      )
    );
  };

  # Transform the bootloader's own command, without duplicating its definition
  # or depending on activation/pre-switch checks (which can be skipped).
  options.system.build.installBootLoader = lib.mkOption {
    apply = command: if names == [ ] then command else wrap command;
  };

  config.assertions = lib.optionals (names != [ ]) [
    {
      assertion = cfg.identityPaths != [ ];
      message = "age.bootloaderSecrets requires age.identityPaths available before bootloader installation.";
    }
    {
      assertion = builtins.all (name: builtins.match "[A-Za-z0-9_][A-Za-z0-9_.-]*" name != null) names;
      message = "age.bootloaderSecrets names must start with a letter, digit, or underscore and contain only letters, digits, underscores, dots, and hyphens.";
    }
  ];
}
