{ lib }:
let
  verbosityLevels = {
    quiet = 0;
    summary = 1;
    progress = 2;
    detailed = 3;
  };
  inherit (lib)
    mkEnableOption
    mkOption
    optional
    optionalString
    types
    ;
in
{
  inherit verbosityLevels;

  validationOption = mkOption {
    type = types.bool;
    default = true;
    description = ''
      Check the public structure of store-backed ciphertext during the build,
      before activation. Runtime file paths are checked by age during activation.
      Authentication and recipient access still require decryption on the target.
    '';
  };

  secretOptions =
    {
      config,
      name,
      secretsDir,
      nameDefaultText ? null,
      pathDefaultText ? null,
    }:
    {
      enable = mkOption {
        type = types.bool;
        default = true;
        description = "Whether to decrypt and install this secret.";
      };
      name = mkOption (
        {
          type = types.str;
          default = name;
          description = "Name of the file used in {option}`age.secretsDir`.";
        }
        // lib.optionalAttrs (nameDefaultText != null) { defaultText = nameDefaultText; }
      );
      file = mkOption {
        type = types.path;
        description = "Age file the secret is loaded from.";
      };
      path = mkOption (
        {
          type = types.str;
          default = "${secretsDir}/${config.name}";
          description = "Path where the decrypted secret is installed.";
        }
        // lib.optionalAttrs (pathDefaultText != null) { defaultText = pathDefaultText; }
      );
      mode = mkOption {
        type = types.str;
        default = "0400";
        description = "Permissions mode of the decrypted secret in a format understood by chmod.";
      };
      trimFinalNewline = mkOption {
        type = types.bool;
        default = false;
        description = "Remove one terminal LF or CRLF after decryption. Other bytes, including embedded newlines, are preserved.";
      };
      symlink = mkEnableOption "symlinking secrets to their destination" // {
        default = true;
      };
    };

  verbosityOption =
    otherOutput:
    mkOption {
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
        This does not affect the agenix command-line tool or ${otherOutput}.
      '';
    };

  installer =
    {
      cfg,
      ageBin,
      locale,
      mountCommand ? "",
      validateFile ? (file: file),
    }:
    let
      verbosityLevel = verbosityLevels.${cfg.verbosity};
      currentGeneration = ''
        _agenix_generation="$(basename "$(readlink "${cfg.secretsDir}")" || echo 0)"
      '';
      setTruePath = secret: ''
        ${
          if secret.symlink || secret.path == "${cfg.secretsDir}/${secret.name}" then
            ''_truePath="${cfg.secretsMountPoint}/$_agenix_generation/${secret.name}"''
          else
            ''_truePath="${secret.path}"''
        }
      '';
      enabledSecrets = lib.filter (secret: secret.enable) (builtins.attrValues cfg.secrets);
      installSecret =
        secret:
        let
          file = validateFile secret.file;
        in
        ''
          ${setTruePath secret}
          ${optionalString (verbosityLevel >= 3) ''echo "decrypting '${secret.file}' to '$_truePath'..."''}
          TMP_FILE="$_truePath.tmp"

          mkdir -p "$(dirname "$_truePath")"
          # shellcheck disable=SC2193,SC2050
          [ "${secret.path}" != "${cfg.secretsDir}/${secret.name}" ] && mkdir -p "$(dirname "${secret.path}")"
          (
            umask u=r,g=,o=
            test -f "${file}" || echo '[agenix] WARNING: encrypted file ${file} does not exist!' >&2
            test -d "$(dirname "$TMP_FILE")" || echo "[agenix] WARNING: $(dirname "$TMP_FILE") does not exist!" >&2
            LANG=${lib.escapeShellArg locale} ${ageBin} --decrypt "''${IDENTITIES[@]}" -o "$TMP_FILE" "${file}"
          )
          ${optionalString secret.trimFinalNewline ''
            # Encode the last byte so empty and binary files remain unambiguous.
            if [ "$(tail -c 1 -- "$TMP_FILE" | od -An -tu1 | tr -d '[:space:]')" = 10 ]; then
              # age creates the file with the restrictive decryption umask.
              chmod u+w "$TMP_FILE"
              truncate --size=-1 -- "$TMP_FILE"
              if [ "$(tail -c 1 -- "$TMP_FILE" | od -An -tu1 | tr -d '[:space:]')" = 13 ]; then
                truncate --size=-1 -- "$TMP_FILE"
              fi
            fi
          ''}
          chmod ${secret.mode} "$TMP_FILE"
          mv -f "$TMP_FILE" "$_truePath"

          ${optionalString secret.symlink ''
            # shellcheck disable=SC2193,SC2050
            [ "${secret.path}" != "${cfg.secretsDir}/${secret.name}" ] && ln -sfT "${cfg.secretsDir}/${secret.name}" "${secret.path}"
          ''}
        '';
      identitySetup = ''
        IDENTITIES=()
        _agenix_identity_paths=( ${lib.escapeShellArgs (map toString cfg.identityPaths)} )
        for identity in "''${_agenix_identity_paths[@]}"; do
          test -f "$identity" || echo "[agenix] WARNING: config.age.identityPaths entry $identity not present!" >&2
          test -r "$identity" || continue
          test -s "$identity" || continue
          IDENTITIES+=(-i "$identity")
        done
        test "''${#IDENTITIES[@]}" -eq 0 && echo "[agenix] WARNING: no readable identities found!" >&2
      '';
      cleanupAndLink = ''
        ${currentGeneration}
        (( ++_agenix_generation ))
        ${optionalString (verbosityLevel >= 2)
          ''echo "[agenix] symlinking new secrets to ${cfg.secretsDir} (generation $_agenix_generation)..."''
        }
        mkdir -p "$(dirname "${cfg.secretsDir}")"
        ln -sfT "${cfg.secretsMountPoint}/$_agenix_generation" "${cfg.secretsDir}"

        (( _agenix_generation > 1 )) && {
        ${optionalString (
          verbosityLevel >= 2
        ) ''echo "[agenix] removing old secrets (generation $(( _agenix_generation - 1 )))..."''}
        rm -rf "${cfg.secretsMountPoint}/$(( _agenix_generation - 1 ))"
        }
      '';
    in
    {
      inherit currentGeneration enabledSecrets setTruePath;
      newGeneration = ''
        ${currentGeneration}
        (( ++_agenix_generation ))
        ${optionalString (
          verbosityLevel >= 2
        ) ''echo "[agenix] creating new generation in ${cfg.secretsMountPoint}/$_agenix_generation"''}
        mkdir -p "${cfg.secretsMountPoint}"
        chmod 0751 "${cfg.secretsMountPoint}"
        ${mountCommand}
        mkdir -p "${cfg.secretsMountPoint}/$_agenix_generation"
        chmod 0751 "${cfg.secretsMountPoint}/$_agenix_generation"
      '';
      installSecrets = builtins.concatStringsSep "\n" (
        (optional (verbosityLevel >= 1) "echo '[agenix] decrypting secrets...'")
        ++ [ identitySetup ]
        ++ (map installSecret enabledSecrets)
        ++ [ cleanupAndLink ]
      );
    };
}
