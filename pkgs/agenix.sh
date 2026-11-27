#!/usr/bin/env bash
# Keep the existing conditional function calls and command substitutions: changing
# their set -e behavior would alter how edit, rekey, and decrypt report failures.
# shellcheck disable=SC2310,SC2312
set -Eeuo pipefail
shopt -s assoc_expand_once 2>/dev/null || true

PACKAGE="agenix"

function show_help () {
  echo "${PACKAGE} - edit, rekey, and check age secret files"
  echo " "
  echo "${PACKAGE} -e FILE [-i PRIVATE_KEY]"
  echo "${PACKAGE} -r [-i PRIVATE_KEY]"
  echo "${PACKAGE} -c"
  echo "${PACKAGE} -d FILE [-i PRIVATE_KEY]"
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

function set_mode() {
  if [[ -n "${MODE}" ]]; then
    err "Cannot combine multiple operation modes (-e, -r, -c, -d)."
  fi
  MODE=$1
}

function set_file() {
  FILE=$1
  while [[ ${FILE} == ./* ]]; do
    FILE=${FILE#./}
  done
  if [[ -z "${FILE}" ]]; then
    err "no FILE specified"
  fi
}

if [[ $# -eq 0 ]]; then
  show_help
  exit 1
fi

MODE=""
FILE=""
HAS_IDENTITY=0
DEFAULT_DECRYPT=(--decrypt)

while [[ $# -gt 0 ]]; do
  case "$1" in
    -h|--help)
      show_help
      exit 0
      ;;
    -e|--edit)
      shift
      set_mode edit
      if [[ $# -gt 0 && -n "$1" ]]; then
        set_file "$1"
      else
        err "no FILE specified"
      fi
      shift
      ;;
    -i|--identity)
      shift
      if [[ $# -gt 0 && -n "$1" ]]; then
        identity_path=$1
        if [[ ${identity_path} != /* ]]; then
          identity_path="${PWD}/${identity_path}"
        fi
        DEFAULT_DECRYPT+=(--identity "${identity_path}")
        HAS_IDENTITY=1
      else
        err "no PRIVATE_KEY specified"
      fi
      shift
      ;;
    -r|--rekey)
      shift
      set_mode rekey
      ;;
    -c|--check)
      shift
      set_mode check
      ;;
    -d|--decrypt)
      shift
      set_mode decrypt
      if [[ $# -gt 0 && -n "$1" ]]; then
        set_file "$1"
      else
        err "no FILE specified"
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

if [[ -z "${MODE}" ]]; then
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
        cwd=$(dirname -- "${cwd}")
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
RULES_DIR=$(cd -- "$(dirname -- "${RULES}")" && pwd -P) || err "Cannot access rules directory for '${RULES}'."
RULES="${RULES_DIR}/$(basename -- "${RULES}")"
if (( legacy_rules_variable )) || [[ -z "${rules_variable}" && ${RULES##*/} == secrets.nix ]]; then
    warn 'warning: RULES and automatic discovery of secrets.nix are deprecated and will be removed in a future version of agenix; use AGENIX_RULES and agenix-rules.nix instead.'
fi
cd -- "${RULES_DIR}" || err "Cannot access rules directory '${RULES_DIR}'."

CLEARTEXT_DIR=""
REENCRYPTED_DIR=""
CHECK_TMP_FILE=""

function cleanup {
    if [[ -n "${CLEARTEXT_DIR}" ]]; then
        rm -rf -- "${CLEARTEXT_DIR}"
        CLEARTEXT_DIR=""
    fi
    if [[ -n "${REENCRYPTED_DIR}" ]]; then
        rm -rf -- "${REENCRYPTED_DIR}"
        REENCRYPTED_DIR=""
    fi
    if [[ -n "${CHECK_TMP_FILE}" ]]; then
        rm -f -- "${CHECK_TMP_FILE}"
        CHECK_TMP_FILE=""
    fi
}
trap cleanup EXIT
trap 'exit 130' INT
trap 'exit 131' QUIT
trap 'exit 143' TERM

# Evaluate a single secret's rule safely via --argstr (no Nix expression interpolation).
function eval_rule {
    local target=$1
    @nixInstantiate@ --json --eval --strict \
        --argstr rulesPath "${RULES}" \
        --argstr file "${target}" \
        -E '{ rulesPath, file }:
            let
                rules = import (/. + rulesPath);
            in
            if !(builtins.hasAttr file rules) then
                throw ("There is no rule for " + file + " in " + rulesPath + ".")
            else
                let
                    rule = builtins.getAttr file rules;
                in {
                    publicKeys = rule.publicKeys;
                    armor = builtins.hasAttr "armor" rule && rule.armor;
                }'
}

# Evaluate all rules in a single nix-instantiate invocation.
function eval_all_rules {
    @nixInstantiate@ --json --eval --strict \
        --argstr rulesPath "${RULES}" \
        -E '{ rulesPath }:
            let
                rules = import (/. + rulesPath);
            in
            builtins.mapAttrs (_: rule: {
                publicKeys = rule.publicKeys;
                armor = builtins.hasAttr "armor" rule && rule.armor;
            }) rules'
}

function decrypt {
    local file=$1 keys=$2 output_file=$3
    local -a decrypt_args=("${DEFAULT_DECRYPT[@]}")
    local has_id=${HAS_IDENTITY}

    if [[ -z "${keys}" ]]; then
        err "There is no rule for ${file} in ${RULES}."
    fi

    if [[ -f "${file}" ]]; then
        if (( ! has_id )); then
            if [[ -f "${HOME}/.ssh/id_rsa" && -r "${HOME}/.ssh/id_rsa" && -s "${HOME}/.ssh/id_rsa" ]]; then
                decrypt_args+=(--identity "${HOME}/.ssh/id_rsa")
                has_id=1
            fi
            if [[ -f "${HOME}/.ssh/id_ed25519" && -r "${HOME}/.ssh/id_ed25519" && -s "${HOME}/.ssh/id_ed25519" ]]; then
                decrypt_args+=(--identity "${HOME}/.ssh/id_ed25519")
                has_id=1
            fi
        fi
        if (( ! has_id )); then
            err "No identity found to decrypt ${file}. Try adding an SSH key at ${HOME}/.ssh/id_rsa or ${HOME}/.ssh/id_ed25519 or using the --identity flag to specify a file."
        fi

        @ageBin@ "${decrypt_args[@]}" -o "${output_file}" -- "${file}" || exit 1
    fi
}

function edit {
    local file=$1 keys armor rule_json cleartext_file reencrypted_file key
    local -a encrypt_args=() editor_cmd=()

    if [[ $# -ge 3 ]]; then
        keys=$2
        armor=$3
    else
        rule_json=$(eval_rule "${file}") || exit 1
        keys=$(@jqBin@ -r '.publicKeys[]' <<< "${rule_json}") || exit 1
        armor=$(@jqBin@ -r '.armor' <<< "${rule_json}") || exit 1
    fi

    if [[ -z "${keys}" ]]; then
        err "There is no rule for ${file} in ${RULES}."
    fi

    CLEARTEXT_DIR=$(@mktempBin@ -d)
    cleartext_file="${CLEARTEXT_DIR}/$(basename -- "${file}")"

    # Piped input replaces the cleartext without needing a decryption identity.
    # Rekeying still needs the old cleartext, even when stdin is not a terminal.
    if [[ -t 0 || "${EDITOR:-}" == ":" ]]; then
        (
            umask 077
            decrypt "${file}" "${keys}" "${cleartext_file}"
        ) || exit 1
    fi

    if [[ -f "${cleartext_file}" ]]; then
        (
            umask 077
            cp -- "${cleartext_file}" "${cleartext_file}.before"
        )
    fi

    # only edit if we're not rekeying
    if [[ "${EDITOR:-}" != ":" ]]; then
        if [[ -t 0 ]]; then
            if [[ -z "${EDITOR:-}" ]]; then
                err "EDITOR is not set. Set the EDITOR environment variable to edit ${file}."
            fi
            read -r -a editor_cmd <<< "${EDITOR}"
            "${editor_cmd[@]}" "${cleartext_file}"
        else
            (
                umask 077
                cat > "${cleartext_file}"
            )
        fi
    fi

    if [[ ! -f "${cleartext_file}" ]]; then
        warn "${file} wasn't created."
        return
    fi
    if [[ -f "${cleartext_file}.before" && "${EDITOR:-}" != ":" ]] && @diffBin@ -q -- "${cleartext_file}.before" "${cleartext_file}" >/dev/null; then
        warn "${file} wasn't changed, skipping re-encryption."
        return
    fi

    if [[ "${armor}" == "true" ]]; then
        encrypt_args+=(--armor)
    fi
    while IFS= read -r key; do
        if [[ -n "${key}" ]]; then
            encrypt_args+=(--recipient "${key}")
        fi
    done <<< "${keys}"

    REENCRYPTED_DIR=$(@mktempBin@ -d)
    reencrypted_file="${REENCRYPTED_DIR}/$(basename -- "${file}")"

    encrypt_args+=(-o "${reencrypted_file}")

    @ageBin@ "${encrypt_args[@]}" < "${cleartext_file}" || exit 1

    mkdir -p -- "$(dirname -- "${file}")"

    mv -f -- "${reencrypted_file}" "${file}"
}

function rekey {
    local rules_json file armor_val rule_keys
    rules_json=$(eval_all_rules) || exit 1

    while IFS= read -r -d '' -u 3 file && IFS= read -r -d '' -u 3 armor_val && IFS= read -r -d '' -u 3 rule_keys; do
        warn "rekeying ${file}..."
        EDITOR=: edit "${file}" "${rule_keys}" "${armor_val}"
        cleanup
    done 3< <(@jqBin@ -j 'to_entries[] | .key + "\u0000" + (.value.armor | tostring) + "\u0000" + (.value.publicKeys | join("\n")) + "\u0000"' <<< "${rules_json}")
}

# age stores the first four bytes of the SSH public key's SHA-256 hash as a
# six-character, unpadded base64 tag in each SSH recipient stanza.
# The first 5 base64 chars of the 32-byte SHA-256 fingerprint match directly;
# the 6th char keeps only its top 2 bits (masking out the low 4 bits from byte 4).
declare -A SSH_TAG_CACHE=()
SSH_TAG_RESULT=""

function ssh_tag_into {
    local key=$1 key_type key_blob cache_key fingerprint prefix c6
    read -r key_type key_blob _ <<< "${key}"
    cache_key="${key_type} ${key_blob}"

    if [[ -v SSH_TAG_CACHE["${cache_key}"] ]]; then
        SSH_TAG_RESULT=${SSH_TAG_CACHE["${cache_key}"]}
        [[ -n "${SSH_TAG_RESULT}" ]]
        return
    fi

    if ! fingerprint=$(printf '%s\n' "${key}" | @sshKeygenBin@ -lf -); then
        SSH_TAG_CACHE["${cache_key}"]=""
        SSH_TAG_RESULT=""
        return 1
    fi
    fingerprint=${fingerprint#*SHA256:}
    fingerprint=${fingerprint%% *}
    if [[ ${#fingerprint} -lt 6 ]]; then
        SSH_TAG_CACHE["${cache_key}"]=""
        SSH_TAG_RESULT=""
        return 1
    fi
    prefix=${fingerprint:0:5}
    c6=${fingerprint:5:1}
    case ${c6} in
        A|B|C|D|E|F|G|H|I|J|K|L|M|N|O|P) c6=A ;;
        Q|R|S|T|U|V|W|X|Y|Z|a|b|c|d|e|f) c6=Q ;;
        g|h|i|j|k|l|m|n|o|p|q|r|s|t|u|v) c6=g ;;
        w|x|y|z|0|1|2|3|4|5|6|7|8|9|+|/) c6=w ;;
        *)
            SSH_TAG_CACHE["${cache_key}"]=""
            SSH_TAG_RESULT=""
            return 1
            ;;
    esac
    SSH_TAG_RESULT="${prefix}${c6}"
    SSH_TAG_CACHE["${cache_key}"]=${SSH_TAG_RESULT}
}

KNOWN_LOADED=0
declare -A KNOWN_KEYS=()
declare -A AMBIGUOUS_KEYS=()

function add_known_key {
    local key=$1 key_type key_blob canonical tag stanza
    read -r key_type key_blob _ <<< "${key}"
    case ${key_type} in
        ssh-ed25519|ssh-rsa) ;;
        *) return 0 ;;
    esac
    canonical="${key_type} ${key_blob}"
    ssh_tag_into "${canonical}" 2>/dev/null || return 0
    tag=${SSH_TAG_RESULT}
    stanza="${key_type} ${tag}"
    if [[ -v KNOWN_KEYS["${stanza}"] && ${KNOWN_KEYS["${stanza}"]} != "${canonical}" ]]; then
        AMBIGUOUS_KEYS["${stanza}"]=1
    else
        KNOWN_KEYS["${stanza}"]=${canonical}
    fi
}

function load_known_keys {
    local rules_json=$1 key
    if (( KNOWN_LOADED )); then
        return 0
    fi
    KNOWN_LOADED=1
    while IFS= read -r key; do
        [[ -n "${key}" ]] || continue
        add_known_key "${key}"
    done < <(@jqBin@ -r '.[].publicKeys[]' <<< "${rules_json}")
    while IFS= read -r key; do
        [[ -n "${key}" ]] || continue
        add_known_key "${key}"
    done < <(@jqBin@ -Rr 'scan("ssh-(?:ed25519|rsa) [A-Za-z0-9+/=]+")' -- "${RULES}")
}

function check_file {
    local file=$1 rule_keys=$2 rules_json=$3 input=$1 line key tag stanza count
    local found_header=0 mismatch=0
    local -A expected=() actual=()
    local -a expected_order=() actual_order=()

    if [[ ! -f ${file} ]]; then
        warn "✗ ${file}: file not found"
        return 1
    fi

    IFS= read -r line < "${file}" || line=""
    line=${line%$'\r'}
    if [[ ${line} == '-----BEGIN AGE ENCRYPTED FILE-----' ]]; then
        CHECK_TMP_FILE=$(@mktempBin@) || return 1
        input=${CHECK_TMP_FILE}
        # shellcheck disable=SC2016
        if ! LC_ALL=C @sedBin@ -n '1d; s/\r$//; /^-----END AGE ENCRYPTED FILE-----$/q0; p; $q1' -- "${file}" | @base64Bin@ --decode > "${input}"; then
            warn "✗ ${file}: invalid age armor"
            rm -f -- "${CHECK_TMP_FILE}"
            CHECK_TMP_FILE=""
            return 1
        fi
    fi

    while IFS= read -r key; do
        [[ -n ${key} ]] || continue
        case ${key} in
            ssh-ed25519\ *|ssh-rsa\ *) ;;
            *)
                warn "✗ ${file}: cannot check non-SSH recipient ${key}"
                if [[ -n "${CHECK_TMP_FILE}" ]]; then
                    rm -f -- "${CHECK_TMP_FILE}"
                    CHECK_TMP_FILE=""
                fi
                return 1
                ;;
        esac
        if ! ssh_tag_into "${key}"; then
            warn "✗ ${file}: invalid SSH recipient ${key}"
            if [[ -n "${CHECK_TMP_FILE}" ]]; then
                rm -f -- "${CHECK_TMP_FILE}"
                CHECK_TMP_FILE=""
            fi
            return 1
        fi
        tag=${SSH_TAG_RESULT}
        stanza="${key%% *} ${tag}"
        if [[ ! -v expected["${stanza}"] ]]; then
            expected["${stanza}"]=${key}
            expected_order+=("${stanza}")
        fi
    done <<< "${rule_keys}"

    {
        if IFS= read -r line && [[ ${line} == 'age-encryption.org/v1' ]]; then
            found_header=1
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
                    count=${actual["${stanza}"]:-0}
                    count=$(( count + 1 ))
                    actual["${stanza}"]=${count}
                    if (( count == 1 )); then
                        actual_order+=("${stanza}")
                    fi
                elif [[ ! ${line} =~ ^[A-Za-z0-9+/]*$ ]]; then
                    break
                fi
            done
        fi
    } < "${input}"

    if [[ -n "${CHECK_TMP_FILE}" ]]; then
        rm -f -- "${CHECK_TMP_FILE}"
        CHECK_TMP_FILE=""
    fi
    if (( found_header != 2 )); then
        warn "✗ ${file}: invalid age header"
        return 1
    fi

    for stanza in "${expected_order[@]}"; do
        if [[ ! -v actual["${stanza}"] ]]; then
            mismatch=1
        fi
    done
    for stanza in "${actual_order[@]}"; do
        count=${actual["${stanza}"]:-0}
        if [[ ! -v expected["${stanza}"] ]] || (( count > 1 )); then
            mismatch=1
        fi
    done

    if (( mismatch )); then
        printf '✗ %s\n' "${file}"
        for stanza in "${expected_order[@]}"; do
            [[ -v actual["${stanza}"] ]] || printf '  missing: %s\n' "${expected["${stanza}"]}"
        done
        for stanza in "${actual_order[@]}"; do
            count=${actual["${stanza}"]:-0}
            if [[ ! -v expected["${stanza}"] ]]; then
                load_known_keys "${rules_json}"
                if [[ -v KNOWN_KEYS["${stanza}"] && ! -v AMBIGUOUS_KEYS["${stanza}"] ]]; then
                    printf '  extra: %s\n' "${KNOWN_KEYS["${stanza}"]}"
                else
                    printf '  extra: %s\n' "${stanza}"
                fi
            elif (( count > 1 )); then
                printf '  extra: %s (duplicate)\n' "${stanza}"
            fi
        done
        return 1
    fi
    printf '✓ %s\n' "${file}"
}

function check {
    local rules_json file rule_keys status=0
    rules_json=$(eval_all_rules) || return 1

    while IFS= read -r -d '' -u 3 file && IFS= read -r -d '' -u 3 rule_keys; do
        check_file "${file}" "${rule_keys}" "${rules_json}" || status=1
    done 3< <(@jqBin@ -j 'to_entries[] | .key + "\u0000" + (.value.publicKeys | join("\n")) + "\u0000"' <<< "${rules_json}")
    return "${status}"
}

case "${MODE}" in
    check)
        check
        exit $?
        ;;
    rekey)
        rekey
        exit 0
        ;;
    decrypt)
        [[ -f "${FILE}" ]] || err "${FILE}: file not found"
        rule_json=$(eval_rule "${FILE}") || exit 1
        keys=$(@jqBin@ -r '.publicKeys[]' <<< "${rule_json}") || exit 1
        decrypt "${FILE}" "${keys}" "-"
        exit 0
        ;;
    edit)
        edit "${FILE}"
        cleanup
        exit 0
        ;;
    *)
        show_help
        exit 1
        ;;
esac
