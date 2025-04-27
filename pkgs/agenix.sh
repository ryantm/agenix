#!/usr/bin/env bash
set -Eeuo pipefail

PACKAGE="agenix"

function show_help () {
  echo "$PACKAGE - edit and rekey age secret files"
  echo " "
  echo "$PACKAGE -c FILE"
  echo "$PACKAGE -e FILE [-i PRIVATE_KEY]"
  echo "$PACKAGE -r [-i PRIVATE_KEY]"
  echo ' '
  echo 'options:'
  echo '-h, --help                show help'
  # shellcheck disable=SC2016
  echo '-c, --create FILE         create or replace FILE using $EDITOR'
  # shellcheck disable=SC2016
  echo '-e, --edit FILE           edits FILE using $EDITOR'
  echo '-r, --rekey               re-encrypts all secrets with specified recipients'
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
  echo ' '
  echo 'RULES environment variable with path to Nix file specifying recipient public keys.'
  echo "Defaults to './secrets.nix'"
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

test $# -eq 0 && (show_help && exit 1)

REKEY=0
ENCRYPT_ONLY=0
DECRYPT_ONLY=0
DEFAULT_DECRYPT=(--decrypt)

while test $# -gt 0; do
  case "$1" in
    -h|--help)
      show_help
      exit 0
      ;;
    -c|--create)
      shift
      ENCRYPT_ONLY=1
      if test $# -gt 0; then
        export FILE=$1
      else
        echo "no FILE specified"
        exit 1
      fi
      shift
      ;;
    -e|--edit)
      shift
      if test $# -gt 0; then
        export FILE=$1
      else
        echo "no FILE specified"
        exit 1
      fi
      shift
      ;;
    -i|--identity)
      shift
      if test $# -gt 0; then
        DEFAULT_DECRYPT+=(--identity "$1")
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
    -d|--decrypt)
      shift
      DECRYPT_ONLY=1
      if test $# -gt 0; then
        export FILE=$1
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

RULES=${RULES:-./secrets.nix}
function cleanup {
    if [ -n "${CLEARTEXT_DIR+x}" ]
    then
        rm -rf "$CLEARTEXT_DIR"
    fi
    if [ -n "${REENCRYPTED_DIR+x}" ]
    then
        rm -rf "$REENCRYPTED_DIR"
    fi
}
trap "cleanup" 0 2 3 15

function keys {
    (@nixInstantiate@ --json --eval --strict -E "(let rules = import $RULES; in rules.\"$1\".publicKeys)" | @jqBin@ -r .[]) || exit 1
}

function decrypt {
    FILE=$1
    KEYS=$2
    if [ -z "$KEYS" ]
    then
        err "There is no rule for $FILE in $RULES."
    fi

    if [ -f "$FILE" ]
    then
        DECRYPT=("${DEFAULT_DECRYPT[@]}")
        if [[ "${DECRYPT[*]}" != *"--identity"* ]]; then
            if [ -f "$HOME/.ssh/id_rsa" ]; then
                DECRYPT+=(--identity "$HOME/.ssh/id_rsa")
            fi
            if [ -f "$HOME/.ssh/id_ed25519" ]; then
                DECRYPT+=(--identity "$HOME/.ssh/id_ed25519")
            fi
        fi
        if [[ "${DECRYPT[*]}" != *"--identity"* ]]; then
          err "No identity found to decrypt $FILE. Try adding an SSH key at $HOME/.ssh/id_rsa or $HOME/.ssh/id_ed25519 or using the --identity flag to specify a file."
        fi

        @ageBin@ "${DECRYPT[@]}" "$FILE" || exit 1
    fi
}

function edit {
    FILE=$1
    KEYS=$(keys "$FILE") || exit 1

    CLEARTEXT_DIR=$(@mktempBin@ -d)
    CLEARTEXT_FILE="$CLEARTEXT_DIR/$(basename "$FILE")"
    DEFAULT_DECRYPT+=(-o "$CLEARTEXT_FILE")

    # Decrypt file
    if [ $ENCRYPT_ONLY -eq 0 ]
    then
      decrypt "$FILE" "$KEYS" || exit 1
      [ ! -f "$CLEARTEXT_FILE" ] || cp "$CLEARTEXT_FILE" "$CLEARTEXT_FILE.before"
    else
      touch "$CLEARTEXT_FILE.before"
    fi

    # Prompt file edit
    [ -t 0 ] || EDITOR='cp /dev/stdin'
    $EDITOR "$CLEARTEXT_FILE"

    # Check file status
    if [ ! -f "$CLEARTEXT_FILE" ]
    then
      warn "$FILE wasn't created."
      return
    fi
    [ $ENCRYPT_ONLY -eq 0 ] && [ -f "$FILE" ] && [ "$EDITOR" != ":" ] && @diffBin@ -q "$CLEARTEXT_FILE.before" "$CLEARTEXT_FILE" && warn "$FILE wasn't changed, skipping re-encryption." && return

    ENCRYPT=()
    # Build recipient list
    while IFS= read -r key
    do
        if [ -n "$key" ]; then
            ENCRYPT+=(--recipient "$key")
        fi
    done <<< "$KEYS"

    REENCRYPTED_DIR=$(@mktempBin@ -d)
    REENCRYPTED_FILE="$REENCRYPTED_DIR/$(basename "$FILE")"

    ENCRYPT+=(-o "$REENCRYPTED_FILE")

    @ageBin@ "${ENCRYPT[@]}" <"$CLEARTEXT_FILE" || exit 1

    mkdir -p "$(dirname "$FILE")"

    mv -f "$REENCRYPTED_FILE" "$FILE"
}

function rekey {
    FILES=$( (@nixInstantiate@ --json --eval -E "(let rules = import $RULES; in builtins.attrNames rules)"  | @jqBin@ -r .[]) || exit 1)

    for FILE in $FILES
    do
        warn "rekeying $FILE..."
        EDITOR=: edit "$FILE"
        cleanup
    done
}

[ $REKEY -eq 1 ] && rekey && exit 0
[ $DECRYPT_ONLY -eq 1 ] && DEFAULT_DECRYPT+=("-o" "-") && decrypt "${FILE}" "$(keys "$FILE")" && exit 0
edit "$FILE" && cleanup && exit 0
