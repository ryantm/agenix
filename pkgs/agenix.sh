#!/usr/bin/env bash
# The recipient checker explicitly handles failures in conditional calls.
# shellcheck disable=SC2310,SC2312
set -Eeuo pipefail

PACKAGE="agenix"

function show_help () {
  echo "${PACKAGE} - edit, rekey, and check age secret files"
  echo " "
  echo "${PACKAGE} -e FILE [-i PRIVATE_KEY] [-j PLUGIN]"
  echo "${PACKAGE} -r [PUBLIC_KEY] [-i PRIVATE_KEY] [-j PLUGIN]"
  echo "${PACKAGE} -c"
  echo ' '
  echo 'options:'
  echo '-h, --help                show help'
  echo "-e, --edit FILE           edits FILE using \$EDITOR"
  echo '-r, --rekey [PUBLIC_KEY]  re-encrypts secrets, optionally selecting a recipient'
  echo '-c, --check               checks encrypted SSH recipients against the rules'
  echo '-d, --decrypt FILE        decrypts FILE to STDOUT'
  echo '-i, --identity            identity to use when decrypting'
  echo '-j PLUGIN                 decrypt using the data-less plugin PLUGIN'
  echo '-v, --verbose             verbose output'
  echo ' '
  echo 'FILE an age-encrypted file'
  echo ' '
  echo 'PRIVATE_KEY a path to a private SSH key used to decrypt file'
  echo ' '
  echo 'PUBLIC_KEY an exact public key string from the rules; only matching secrets are rekeyed'
  echo ' '
  echo 'EDITOR environment variable of editor to use when editing FILE'
  echo ' '
  echo 'If STDIN is not interactive, its contents replace the secret.'
  echo 'Piped input replaces a secret without decrypting it first.'
  echo ' '
  echo 'AGENIX_RULES environment variable with path to Nix file specifying recipient public keys.'
  echo 'Searches the current directory for agenix-rules.nix, then secrets.nix.'
  echo 'Searches parent directories for agenix-rules.nix only.'
  echo "Resolves relative secret paths from the selected rules file's directory."
  echo ' '
  echo "agenix version: @version@"
  echo "age binary path: @ageBin@"
  echo "age version: $(@ageBin@ --version)"
}

function warn() {
  printf '%s\n' "$*" >&2
}

function err() {
  warn "$*"
  exit 1
}

function set_file() {
  FILE=$1
  while [[ ${FILE} == ./* ]]; do
    FILE=${FILE#./}
  done
  [[ -n ${FILE} ]] || err 'FILE must not be empty'
}

function set_operation() {
  [[ -z ${OPERATION} ]] || err 'Select only one of --edit, --decrypt, --rekey, or --check.'
  OPERATION=$1
}

OPERATION=
FILE=
REKEY_PUBLIC_KEY=
DEFAULT_DECRYPT=(--decrypt)
EXPLICIT_IDENTITY=0

while test $# -gt 0; do
  case "$1" in
    -h|--help)
      show_help
      exit 0
      ;;
    -e|--edit)
      set_operation edit
      shift
      if test $# -gt 0; then
        set_file "$1"
      else
        echo "no FILE specified"
        exit 1
      fi
      shift
      ;;
    -i|--identity)
      shift
      if test $# -gt 0; then
        identity_path=$1
        if [[ ${identity_path} != /* ]]; then
          identity_path="${PWD}/${identity_path}"
        fi
        DEFAULT_DECRYPT+=(--identity "${identity_path}")
        EXPLICIT_IDENTITY=1
      else
        echo "no PRIVATE_KEY specified"
        exit 1
      fi
      shift
      ;;
    -j)
      shift
      if [[ $# -eq 0 || -z $1 || $1 == -* ]]; then
        err 'no PLUGIN specified'
      fi
      DEFAULT_DECRYPT+=(-j "$1")
      EXPLICIT_IDENTITY=1
      shift
      ;;
    -r|--rekey)
      set_operation rekey
      shift
      if [[ $# -gt 0 && $1 != -* ]]; then
        REKEY_PUBLIC_KEY="$1"
        [[ -n ${REKEY_PUBLIC_KEY} ]] || err 'PUBLIC_KEY must not be empty'
        shift
      fi
      ;;
    -c|--check)
      set_operation check
      shift
      ;;
    -d|--decrypt)
      set_operation decrypt
      shift
      if test $# -gt 0; then
        set_file "$1"
      else
        echo "no FILE specified"
        exit 1
      fi
      shift
      ;;
    -v|--verbose)
      shift
      set -x
      ;;
    *)
      show_help
      exit 1
      ;;
  esac
done

if [[ -z ${OPERATION} ]]; then
  show_help
  exit 1
fi

function find_rules {
    # Keep secrets.nix discovery limited to the current directory.
    local cwd="${PWD}"
    if [[ -f "${cwd}/agenix-rules.nix" ]]; then
        printf '%s\n' "${cwd}/agenix-rules.nix"
        return 0
    fi
    if [[ -f "${cwd}/secrets.nix" ]]; then
        printf '%s\n' "${cwd}/secrets.nix"
        return 0
    fi
    while [[ "${cwd}" != '/' ]]
    do
        cwd=${cwd%/*}
        [[ -n ${cwd} ]] || cwd=/
        if [[ -f "${cwd}/agenix-rules.nix" ]]; then
            printf '%s\n' "${cwd}/agenix-rules.nix"
            return 0
        fi
    done
    err "${PACKAGE} needs a rules file. Set AGENIX_RULES, create agenix-rules.nix in the current directory or a parent, or create secrets.nix in the current directory."
}

legacy_rules_variable=0
if [[ -v AGENIX_RULES ]]; then
    RULES=${AGENIX_RULES}
    rules_variable=AGENIX_RULES
elif [[ -v RULES ]]; then
    legacy_rules_variable=1
    rules_variable=RULES
else
    RULES=$(find_rules) || exit 1
    rules_variable=''
fi

if [[ -n "${rules_variable}" && ! -f "${RULES}" ]]; then
    err "Rules file '${RULES}' specified via the variable ${rules_variable} not found."
fi
[[ -r "${RULES}" ]] || err "Cannot read rules file '${RULES}'."
rules_parent=.
if [[ ${RULES} == */* ]]; then
    rules_parent=${RULES%/*}
    [[ -n ${rules_parent} ]] || rules_parent=/
fi
# The final /. preserves directory names ending in a newline in this substitution.
RULES_DIR=$(cd -P -- "${rules_parent}" && printf '%s/.' "${PWD}") || err "Cannot access rules directory for '${RULES}'."
RULES="${RULES_DIR}/${RULES##*/}"
if (( legacy_rules_variable )) || [[ -z "${rules_variable}" && ${RULES##*/} == secrets.nix ]]; then
    warn 'warning: RULES and automatic discovery of secrets.nix are deprecated and will be removed in a future version of agenix; use AGENIX_RULES and agenix-rules.nix instead.'
fi
cd "${RULES_DIR}" || err "Cannot access rules directory '${RULES_DIR}'."

function cleanup {
    if [[ -n "${CLEARTEXT_DIR+x}" ]]
    then
        rm -rf -- "${CLEARTEXT_DIR}"
        unset CLEARTEXT_DIR
    fi
    if [[ -n "${REENCRYPTED_DIR+x}" ]]
    then
        rm -rf -- "${REENCRYPTED_DIR}"
        unset REENCRYPTED_DIR
    fi
}
trap cleanup EXIT
trap 'exit 130' INT
trap 'exit 131' QUIT
trap 'exit 143' TERM

# Pass paths and filenames as data, and force only fields used by this operation.
RULE_DATA=$(@nixInstantiate@ --impure --json --eval --strict \
    --argstr rulesPath "${RULES}" --argstr operation "${OPERATION}" \
    --argstr file "${FILE}" --argstr recipient "${REKEY_PUBLIC_KEY}" \
    -E '{ rulesPath, operation, file, recipient }:
      let
        rules = import (builtins.toPath rulesPath);
        names = if operation == "edit" || operation == "decrypt"
          then [ file ] else builtins.attrNames rules;
        selected = builtins.filter
          (name: recipient == "" || builtins.elem recipient (builtins.getAttr name rules).publicKeys)
          names;
      in builtins.listToAttrs (map (name: let rule = builtins.getAttr name rules; in {
        inherit name;
        value = {
          publicKeys = rule.publicKeys;
          armor = if operation == "edit" || operation == "rekey"
            then rule.armor or false else false;
        };
      }) selected)') || exit 1

@jqBin@ -e 'all(to_entries[];
    (.key | length > 0 and index("\u0000") == null) and
    (.value.armor | type == "boolean") and
    (.value.publicKeys | type == "array" and length > 0 and
      all(.[]; type == "string" and length > 0 and index("\u0000") == null)))' \
    <<< "${RULE_DATA}" >/dev/null || err 'Rules require a nonempty filename, a nonempty list of public key strings, and a boolean armor setting.'

mapfile -d '' -t FILES < <(@jqBin@ -jr 'keys[] + "\u0000"' <<< "${RULE_DATA}")
if [[ -n ${REKEY_PUBLIC_KEY} && ${#FILES[@]} -eq 0 ]]; then
    err 'No secrets in the rules match PUBLIC_KEY'
fi

function load_rule {
    mapfile -d '' -t RULE_KEYS < <(@jqBin@ -jr --arg file "$1" \
        '.[$file].publicKeys[] + "\u0000"' <<< "${RULE_DATA}")
    ARMOR=$(@jqBin@ -r --arg file "$1" '.[$file].armor' <<< "${RULE_DATA}")
}

function decrypt {
    local file=$1 output=$2 have_identity=${EXPLICIT_IDENTITY}
    local -a args=("${DEFAULT_DECRYPT[@]}")
    [[ -f ${file} ]] || err "${file} does not exist."
    if (( ! have_identity )); then
        if [[ -f "${HOME}/.ssh/id_rsa" ]]; then
            args+=(--identity "${HOME}/.ssh/id_rsa")
            have_identity=1
        fi
        if [[ -f "${HOME}/.ssh/id_ed25519" ]]; then
            args+=(--identity "${HOME}/.ssh/id_ed25519")
            have_identity=1
        fi
    fi
    if (( ! have_identity )); then
        err "No identity found to decrypt ${file}. Try adding an SSH key at ${HOME}/.ssh/id_rsa or ${HOME}/.ssh/id_ed25519, using --identity to specify a file, or using -j to specify a plugin."
    fi
    @ageBin@ "${args[@]}" -o "${output}" -- "${file}" || exit 1
}

function prepare_cleartext {
    CLEARTEXT_DIR=$(@mktempBin@ -d)
    CLEARTEXT_FILE="${CLEARTEXT_DIR}/${1##*/}"
}

function edit {
    local file=$1
    prepare_cleartext "${file}"

    # Piped input replaces the cleartext without needing a decryption identity.
    # Preserve EDITOR=: as a user-requested no-op editor, including without a tty.
    if [[ -f ${file} && ( -t 0 || ${EDITOR:-} == : ) ]]; then
      decrypt "${file}" "${CLEARTEXT_FILE}"
    fi

    [[ ! -f "${CLEARTEXT_FILE}" ]] || cp -- "${CLEARTEXT_FILE}" "${CLEARTEXT_FILE}.before"

    if [[ "${EDITOR:-}" != ":" ]]; then
      if [[ -t 0 ]]; then
        [[ -n ${EDITOR:-} ]] || err 'Set EDITOR to edit a secret interactively.'
        ${EDITOR} "${CLEARTEXT_FILE}" || err "Editor failed for ${file}."
      else
        cat > "${CLEARTEXT_FILE}"
      fi
    fi

    if [[ ! -f "${CLEARTEXT_FILE}" ]]
    then
      warn "${file} wasn't created."
      return
    fi
    if [[ -f ${CLEARTEXT_FILE}.before && ${EDITOR:-} != : ]] && \
        @diffBin@ -q -- "${CLEARTEXT_FILE}.before" "${CLEARTEXT_FILE}"; then
        warn "${file} wasn't changed, skipping re-encryption."
        return
    fi
    encrypt "${file}"
}

function encrypt {
    local file=$1 key directory=.
    local -a args=()
    if [[ "${ARMOR}" == "true" ]]; then
        args+=(--armor)
    fi
    for key in "${RULE_KEYS[@]}"; do
        args+=(--recipient "${key}")
    done

    # Publish with a same-filesystem rename even when TMPDIR is elsewhere.
    # Keep plaintext in CLEARTEXT_DIR; only encrypted output goes here.
    if [[ ${file} == */* ]]; then
        directory=${file%/*}
        [[ -n ${directory} ]] || directory=/
    fi
    mkdir -p -- "${directory}"
    REENCRYPTED_DIR=$(@mktempBin@ -d -- "${directory}/.agenix.XXXXXXXXXX")
    local output="${REENCRYPTED_DIR}/${file##*/}"
    @ageBin@ "${args[@]}" -o "${output}" <"${CLEARTEXT_FILE}" || exit 1
    mv -f -- "${output}" "${file}"
}

function rekey {
    warn "rekeying $1..."
    prepare_cleartext "$1"
    decrypt "$1" "${CLEARTEXT_FILE}"
    encrypt "$1"
}

# age stores the first four bytes of the SSH public key's SHA-256 hash as a
# six-character, unpadded base64 tag in each SSH recipient stanza.
function ssh_tag {
    local fingerprint
    fingerprint=$(printf '%s\n' "$1" | @sshKeygenBin@ -lf -) || return 1
    fingerprint=${fingerprint#*SHA256:}
    fingerprint=${fingerprint%% *}
    printf '%s=' "${fingerprint}" | @base64Bin@ --decode | @headBin@ -c 4 | @base64Bin@ | @trBin@ -d '=\n'
}

function check_file {
    local file=$1 rule_keys=$2 input=$1 line key tag stanza found_header=0 mismatch=0
    local -A expected=() actual=() known=() ambiguous=()
    local -a expected_order=() actual_order=()

    if [[ ! -f ${file} ]]; then
        warn "✗ ${file}: file not found"
        return 1
    fi

    IFS= read -r line < "${file}" || true
    if [[ ${line} == '-----BEGIN AGE ENCRYPTED FILE-----' ]]; then
        input=$(@mktempBin@) || return 1
        if ! @sedBin@ '1d; /^-----END AGE ENCRYPTED FILE-----/,$d' -- "${file}" | @base64Bin@ --decode > "${input}"; then
            warn "✗ ${file}: invalid age armor"
            rm -f -- "${input}"
            return 1
        fi
    fi

    while IFS= read -r key; do
        [[ -n ${key} ]] || continue
        case ${key} in
            ssh-ed25519\ *|ssh-rsa\ *) ;;
            *) warn "✗ ${file}: cannot check non-SSH recipient ${key}"; [[ ${input} == "${file}" ]] || rm -f -- "${input}"; return 1 ;;
        esac
        tag=$(ssh_tag "${key}") || { warn "✗ ${file}: invalid SSH recipient ${key}"; [[ ${input} == "${file}" ]] || rm -f -- "${input}"; return 1; }
        stanza="${key%% *} ${tag}"
        if [[ ! -v expected[${stanza}] ]]; then
            expected[${stanza}]=${key}
            expected_order+=("${stanza}")
        fi
    done <<< "${rule_keys}"

    # A stanza only contains a short tag, so recover a full key when it is
    # still present as a literal elsewhere in the rules file.
    while IFS= read -r key; do
        tag=$(ssh_tag "${key}" 2>/dev/null) || continue
        stanza="${key%% *} ${tag}"
        if [[ -v known[${stanza}] && ${known[${stanza}]} != "${key}" ]]; then
            ambiguous[${stanza}]=1
        else
            known[${stanza}]=${key}
        fi
    done < <(@jqBin@ -Rr 'scan("ssh-(?:ed25519|rsa) [A-Za-z0-9+/=]+")' -- "${RULES}")

    if IFS= read -r line < "${input}" && [[ ${line} == 'age-encryption.org/v1' ]]; then
        found_header=1
    fi
    if (( found_header )); then
        while IFS= read -r line; do
            if [[ ${line} == '--- '* ]]; then
                found_header=2
                break
            fi
            if [[ ${line} == '-> '* ]]; then
                read -r _ key tag _ <<< "${line}"
                # age can add random GREASE stanzas to exercise parsers.
                [[ ${key} == *-grease ]] && continue
                stanza="${key} ${tag}"
                actual[${stanza}]=$(( ${actual[${stanza}]:-0} + 1 ))
                actual_order+=("${stanza}")
            fi
        done < <(@sedBin@ '1d; /^--- /q' -- "${input}")
    fi
    [[ ${input} == "${file}" ]] || rm -f -- "${input}"
    if (( found_header != 2 )); then
        warn "✗ ${file}: invalid age header"
        return 1
    fi

    for stanza in "${expected_order[@]}"; do
        if [[ ! -v actual[${stanza}] ]]; then
            mismatch=1
        fi
    done
    for stanza in "${actual_order[@]}"; do
        if [[ ! -v expected[${stanza}] || ${actual[${stanza}]} -gt 1 ]]; then
            mismatch=1
        fi
    done

    if (( mismatch )); then
        printf '✗ %s\n' "${file}"
        for stanza in "${expected_order[@]}"; do
            [[ -v actual[${stanza}] ]] || printf '  missing: %s\n' "${expected[${stanza}]}"
        done
        for stanza in "${actual_order[@]}"; do
            if [[ ! -v expected[${stanza}] ]]; then
                if [[ -v known[${stanza}] && ! -v ambiguous[${stanza}] ]]; then
                    printf '  extra: %s\n' "${known[${stanza}]}"
                else
                    printf '  extra: %s\n' "${stanza}"
                fi
            elif (( actual[${stanza}] > 1 )); then
                printf '  extra: %s (duplicate)\n' "${stanza}"
                actual[${stanza}]=1
            fi
        done
        return 1
    fi
    printf '✓ %s\n' "${file}"
}

status=0
for file in "${FILES[@]}"; do
    load_rule "${file}"
    case ${OPERATION} in
        check) check_file "${file}" "$(printf '%s\n' "${RULE_KEYS[@]}")" || status=1 ;;
        rekey) rekey "${file}" ;;
        decrypt) decrypt "${file}" - ;;
        edit) edit "${file}" ;;
        *) err "Unknown operation: ${OPERATION}" ;;
    esac
    cleanup
done
exit "${status}"
