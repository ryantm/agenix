{ config, lib, pkgs, ... }:

with lib;

let
  cfg = config.age;
  users = config.users.users;

  identities = builtins.concatStringsSep " " (map (path: "-i ${path}") cfg.sshKeyPaths);
  installSecret = secretType: ''
    TMP_FILE="${secretType.path}.tmp"
    (umask 0400; ${pkgs.age}/bin/age --decrypt ${identities} -o "$TMP_FILE" "${secretType.file}")
    chmod ${secretType.mode} "$TMP_FILE"
    chown ${secretType.owner}:${secretType.group} "$TMP_FILE"
    mv -f "$TMP_FILE" '${secretType.path}'
  '';
  installAllSecrets = builtins.concatStringsSep "\n" (map installSecret (builtins.attrValues cfg.secrets));

  secretType = types.submodule ({ config, ... }: {
    options = {
      name = mkOption {
        type = types.str;
        default = config._module.args.name;
        description = ''
          Name of the file used in /run/secrets
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
          default = "/run/secrets/${config.name}";
          description = ''
            Path where the decrypted secret is installed.
          '';
        };
      mode = mkOption {
        type = types.str;
        default = "0400";
        description = ''
          Permissions mode of the in octal.
        '';
      };
      owner = mkOption {
        type = types.str;
        default = "root";
        description = ''
          User of the file.
        '';
      };
      group = mkOption {
        type = types.str;
        default = users.${config.owner}.group;
        description = ''
          Group of the file.
        '';
      };
    };
  });
in {
  options.age = {
    secrets = mkOption {
      type = types.attrsOf secretType;
      default = {};
      description = ''
        Attrset of secrets.
      '';
    };
    sshKeyPaths = mkOption {
      type = types.listOf types.path;
      default = if config.services.openssh.enable then
                  map (e: e.path) (lib.filter (e: e.type == "rsa" || e.type == "ed25519") config.services.openssh.hostKeys)
                else [];
      description = ''
        Path to SSH keys to be used as identities in age decryption.
      '';
    };
  };
  config = mkIf (cfg.secrets != {}) {
    assertions = [{
      assertion = cfg.sshKeyPaths != [];
      message = "age.sshKeyPaths must be set.";
    }];

    system.activationScripts.setup-secrets = stringAfter [ "users" "groups" ] installAllSecrets;
  };
}
