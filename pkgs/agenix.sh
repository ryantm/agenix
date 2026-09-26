#!/usr/bin/env bash
# Keep the existing conditional function calls and command substitutions: changing
# their set -e behavior would alter how edit, rekey, and decrypt report failures.
# shellcheck disable=SC2310,SC2312
set -Eeuo pipefail

PACKAGE="agenix"

function show_help () {
  echo "${PACKAGE} - edit, rekey, and check age secret files"
  echo " "
  echo "${PACKAGE} -e FILE [-i PRIVATE_KEY]"
  echo "${PACKAGE} -r [-i PRIVATE_KEY]"
  echo "${PACKAGE} -c"
  echo ' '
  echo 'options:'
  echo '-h, --help                show help'
  echo "-e, --edit FILE           edits FILE using \$EDITOR"
  echo '-r, --rekey               re-encrypts all secrets with specified recipients'
  echo '-c, --check               checks encrypted SSH recipients against the rules'
  echo '-d, --decrypt FILE        decrypts FILE to STDOUT'
  echo '-i, --identity            identity to use when decrypting'
  echo '-v, --verbose             verbose output'
  echo ' '
  echo 'FILE an age-encrypted file'
  echo ' '
  echo 'PRIVATE_KEY a path to a private SSH key used to decrypt file'
  echo ' '
  echo 'EDITOR environment variable of editor to use when editing FILE'
  echo ' '
  echo 'If STDIN is not interactive, EDITOR will be set to "cp /dev/stdin"'
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
  export FILE
}

test $# -eq 0 && (show_help && exit 1)

REKEY=0
CHECK=0
DECRYPT_ONLY=0
DEFAULT_DECRYPT=(--decrypt)

while test $# -gt 0; do
  case "$1" in
    -h|--help)
      show_help
      exit 0
      ;;
    -e|--edit)
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
      else
        echo "no PRIVATE_KEY specified"
        exit 1
      fi
      shift
      ;;
    -r|--rekey)
      shift
      REKEY=1
      ;;
    -c|--check)
      shift
      CHECK=1
      ;;
    -d|--decrypt)
      shift
      DECRYPT_ONLY=1
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
        cwd=$(dirname "${cwd}")
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
# Nix path literals need an explicit ./ prefix for relative bare filenames.
case ${RULES} in
    /*|./*|../*) ;;
    *) RULES="./${RULES}" ;;
esac
RULES_DIR=$(cd "$(dirname "${RULES}")" && pwd -P) || err "Cannot access rules directory for '${RULES}'."
RULES="${RULES_DIR}/$(basename "${RULES}")"
if (( legacy_rules_variable )) || [[ -z "${rules_variable}" && ${RULES##*/} == secrets.nix ]]; then
    warn 'warning: RULES and automatic discovery of secrets.nix are deprecated and will be removed in a future version of agenix; use AGENIX_RULES and agenix-rules.nix instead.'
fi
cd "${RULES_DIR}" || err "Cannot access rules directory '${RULES_DIR}'."

function cleanup {
    if [[ -n "${CLEARTEXT_DIR+x}" ]]
    then
        rm -rf -- "${CLEARTEXT_DIR}"
    fi
    if [[ -n "${REENCRYPTED_DIR+x}" ]]
    then
        rm -rf -- "${REENCRYPTED_DIR}"
    fi
}
trap "cleanup" 0 2 3 15

function keys {
    (@nixInstantiate@ --json --eval --strict -E "(let rules = import ${RULES}; in rules.\"$1\".publicKeys)" | @jqBin@ -r .[]) || exit 1
}

function armor {
    (@nixInstantiate@ --json --eval --strict -E "(let rules = import ${RULES}; in (builtins.hasAttr \"armor\" rules.\"$1\" && rules.\"$1\".armor))") || exit 1
}

function decrypt {
    FILE=$1
    KEYS=$2
    if [[ -z "${KEYS}" ]]
    then
        err "There is no rule for ${FILE} in ${RULES}."
    fi

    if [[ -f "${FILE}" ]]
    then
        DECRYPT=("${DEFAULT_DECRYPT[@]}")
        if [[ "${DECRYPT[*]}" != *"--identity"* ]]; then
            if [[ -f "${HOME}/.ssh/id_rsa" ]]; then
                DECRYPT+=(--identity "${HOME}/.ssh/id_rsa")
            fi
            if [[ -f "${HOME}/.ssh/id_ed25519" ]]; then
                DECRYPT+=(--identity "${HOME}/.ssh/id_ed25519")
            fi
        fi
        if [[ "${DECRYPT[*]}" != *"--identity"* ]]; then
          err "No identity found to decrypt ${FILE}. Try adding an SSH key at ${HOME}/.ssh/id_rsa or ${HOME}/.ssh/id_ed25519 or using the --identity flag to specify a file."
        fi

        @ageBin@ "${DECRYPT[@]}" -- "${FILE}" || exit 1
    fi
}

function edit {
    FILE=$1
    KEYS=$(keys "${FILE}") || exit 1
    ARMOR=$(armor "${FILE}") || exit 1

    CLEARTEXT_DIR=$(@mktempBin@ -d)
    CLEARTEXT_FILE="${CLEARTEXT_DIR}/$(basename -- "${FILE}")"
    DEFAULT_DECRYPT+=(-o "${CLEARTEXT_FILE}")

    # Piped input replaces the cleartext without needing a decryption identity.
    # Rekeying still needs the old cleartext, even when stdin is not a terminal.
    if [[ -t 0 || "${EDITOR:-}" == ":" ]]; then
      decrypt "${FILE}" "${KEYS}" || exit 1
    fi

    [[ ! -f "${CLEARTEXT_FILE}" ]] || cp -- "${CLEARTEXT_FILE}" "${CLEARTEXT_FILE}.before"

    # only edit if we're not rekeying
    if [[ "${EDITOR:-}" != ":" ]]; then
      [[ -t 0 ]] || EDITOR='cp -- /dev/stdin'

      ${EDITOR} "${CLEARTEXT_FILE}"
    fi

    if [[ ! -f "${CLEARTEXT_FILE}" ]]
    then
      warn "${FILE} wasn't created."
      return
    fi
    [[ -f "${CLEARTEXT_FILE}.before" ]] && [[ "${EDITOR:-}" != ":" ]] && @diffBin@ -q -- "${CLEARTEXT_FILE}.before" "${CLEARTEXT_FILE}" && warn "${FILE} wasn't changed, skipping re-encryption." && return

    ENCRYPT=()
    if [[ "${ARMOR}" == "true" ]]; then
        ENCRYPT+=(--armor)
    fi
    while IFS= read -r key
    do
        if [[ -n "${key}" ]]; then
            ENCRYPT+=(--recipient "${key}")
        fi
    done <<< "${KEYS}"

    REENCRYPTED_DIR=$(@mktempBin@ -d)
    REENCRYPTED_FILE="${REENCRYPTED_DIR}/$(basename -- "${FILE}")"

    ENCRYPT+=(-o "${REENCRYPTED_FILE}")

    @ageBin@ "${ENCRYPT[@]}" <"${CLEARTEXT_FILE}" || exit 1

    mkdir -p -- "$(dirname -- "${FILE}")"

    mv -f -- "${REENCRYPTED_FILE}" "${FILE}"
}

function rekey {
    FILES=$( (@nixInstantiate@ --json --eval -E "(let rules = import ${RULES}; in builtins.attrNames rules)"  | @jqBin@ -r .[]) || exit 1)

    for FILE in ${FILES}
    do
        warn "rekeying ${FILE}..."
        EDITOR=: edit "${FILE}"
        cleanup
    done
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
    local -A expected=() actual=()
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
                printf '  extra: %s\n' "${stanza}"
            elif (( actual[${stanza}] > 1 )); then
                printf '  extra: %s (duplicate)\n' "${stanza}"
                actual[${stanza}]=1
            fi
        done
        return 1
    fi
    printf '✓ %s\n' "${file}"
}

function check {
    local files file rule_keys status=0
    files=$(@nixInstantiate@ --json --eval -E "(let rules = import ${RULES}; in builtins.attrNames rules)" | @jqBin@ -r .[]) || return 1
    [[ -n ${files} ]] || return 0
    while IFS= read -r file; do
        rule_keys=$(keys "${file}") || return 1
        check_file "${file}" "${rule_keys}" || status=1
    done <<< "${files}"
    return "${status}"
}

if [[ ${CHECK} -eq 1 ]]; then
    check
    exit $?
fi
[[ ${REKEY} -eq 1 ]] && rekey && exit 0
[[ ${DECRYPT_ONLY} -eq 1 ]] && DEFAULT_DECRYPT+=("-o" "-") && decrypt "${FILE}" "$(keys "${FILE}")" && exit 0
edit "${FILE}" && cleanup && exit 0
