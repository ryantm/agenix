{
  config,
  lib,
  pkgs,
  ...
}:
let
  cfg = config.age.identityUnlock;
  directory = "/run/agenix-unlocked-identity";
  ask = pkgs.writeShellScript "agenix-identity-askpass" ''
    exec ${config.systemd.package}/bin/systemd-ask-password \
      --no-tty --timeout=${toString cfg.timeout} --id=agenix-identity-unlock \
      -- ${lib.escapeShellArg cfg.prompt}
  '';
  batchpass = pkgs.writeShellScriptBin "age-plugin-batchpass" ''
    # Open the pipe inside the plugin process, so age's process spawning cannot
    # close it. The passphrase is never placed in argv or the environment.
    unset AGE_PASSPHRASE
    exec 3< <(${ask})
    export AGE_PASSPHRASE_FD=3
    exec ${pkgs.age}/bin/age-plugin-batchpass "$@"
  '';
  lock = pkgs.writeShellScript "agenix-lock-identity" ''
    set -e
    if ${pkgs.util-linux}/bin/mountpoint -q ${directory}; then
      ${pkgs.coreutils}/bin/rm -f -- ${cfg.path}
      ${pkgs.util-linux}/bin/umount ${directory}
    fi
  '';
  unlock = lib.getExe (
    pkgs.writeShellApplication {
      name = "agenix-unlock-identity";
      runtimeInputs = [
        pkgs.coreutils
        pkgs.util-linux
      ];
      text = ''
        umask 077
        if ! mountpoint -q ${directory}; then
          mount -t ramfs none ${directory} -o mode=0700,nodev,nosuid,noexec
        fi
        stage="$(mktemp -d ${directory}/.stage.XXXXXXXX)"
        trap 'rm -rf -- "$stage"' EXIT
        trap 'exit 130' INT
        trap 'exit 143' TERM
        ${
          if cfg.format == "ssh" then
            ''
              cp -- ${lib.escapeShellArg (toString cfg.file)} "$stage/key"
              chmod 0600 "$stage/key"
              SSH_ASKPASS=${ask} SSH_ASKPASS_REQUIRE=force \
                ${pkgs.openssh}/bin/ssh-keygen -q -p -N "" -f "$stage/key" </dev/null >/dev/null
            ''
          else
            ''
              PATH=${lib.makeBinPath [ batchpass ]}:"$PATH" \
                ${pkgs.age}/bin/age --decrypt -j batchpass \
                --output "$stage/key" -- ${lib.escapeShellArg (toString cfg.file)}
              # This format intentionally holds native age identities.
              ${pkgs.age}/bin/age-keygen -y "$stage/key" >/dev/null
            ''
        }
        test -s "$stage/key"
        chmod 0400 "$stage/key"
        mv -fT -- "$stage/key" ${cfg.path}
      '';
    }
  );
  earlyUsers = config.services.userborn.enable || config.systemd.sysusers.enable;
  earlyUnlock = earlyUsers && config.age.installationMode == "activation";
in
{
  imports = [ ./age.nix ];
  options.age.identityUnlock = {
    enable = lib.mkEnableOption "unlocking an encrypted identity through systemd password agents";
    file = lib.mkOption {
      type = lib.types.path;
      description = "Passphrase-encrypted SSH key or age-encrypted native identity file.";
    };
    format = lib.mkOption {
      type = lib.types.enum [
        "ssh"
        "age"
      ];
      default = "ssh";
      description = "Encryption format of the identity: an OpenSSH private key, or a native age identity encrypted with age -p.";
    };
    prompt = lib.mkOption {
      type = lib.types.str;
      default = "Passphrase for agenix identity:";
      description = "Prompt sent to systemd password agents.";
    };
    timeout = lib.mkOption {
      type = lib.types.ints.positive;
      default = 120;
      description = "Seconds to wait for a password agent to answer.";
    };
    path = lib.mkOption {
      type = lib.types.str;
      readOnly = true;
      default = "${directory}/key";
      description = "Root-only unlocked identity on ramfs, removed when the unlock service stops.";
    };
  };
  config = lib.mkIf cfg.enable {
    age.identityPaths = lib.mkBefore [ cfg.path ];
    age.installationMode = lib.mkDefault "systemd";
    assertions = [
      {
        assertion = config.age.installationMode == "systemd" || earlyUsers;
        message = "age.identityUnlock needs systemd installation mode, or Userborn/sysusers for early secret decryption.";
      }
      {
        assertion = !earlyUnlock || cfg.format == "age";
        message = "Early age.identityUnlock requires format = age: ssh-keygen needs user records before it can unlock an SSH identity.";
      }
    ];
    systemd.services.agenix-unlock-identity = {
      description = "Unlock the agenix identity";
      wantedBy = [ "sysinit.target" ];
      before = [
        "agenix-install-secrets.service"
        "shutdown.target"
      ];
      after = [ "systemd-remount-fs.service" ] ++ lib.optional (!earlyUnlock) "local-fs.target";
      conflicts = [ "shutdown.target" ];
      unitConfig = {
        DefaultDependencies = false;
        RequiresMountsFor = [ (toString cfg.file) ];
      };
      serviceConfig = {
        Type = "oneshot";
        RemainAfterExit = true;
        RuntimeDirectory = "agenix-unlocked-identity";
        RuntimeDirectoryMode = "0700";
        UMask = "0077";
        TimeoutStartSec = cfg.timeout + 15;
        ExecStart = unlock;
        ExecStopPost = lock;
      };
    };
    systemd.services.agenix-install-secrets = lib.mkIf config.age.enable {
      requires = [ "agenix-unlock-identity.service" ];
      after = [ "agenix-unlock-identity.service" ];
    };
  };
}
