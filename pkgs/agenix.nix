{writeShellScriptBin, runtimeShell, age} :
writeShellScriptBin "agenix" ''
set -Eeuo pipefail

PACKAGE="agenix"

function show_help () {
  echo "$PACKAGE - edit and rekey age secret files"
  echo " "
  echo "$PACKAGE -e FILE [-i PRIVATE_KEY]"
  echo "$PACKAGE -r [-i PRIVATE_KEY]"
  echo ' '
  echo 'options:'
  echo '-h, --help                show help'
  echo '-e, --edit FILE           edits FILE using $EDITOR'
  echo '-r, --rekey               re-encrypts all secrets with specified recipients'
  echo '-i, --identity            identity to use when decrypting'
  echo ' '
  echo 'FILE an age-encrypted file'
  echo ' '
  echo 'PRIVATE_KEY a path to a private SSH key used to decrypt file'
  echo ' '
  echo 'EDITOR environment variable of editor to use when editing FILE'
  echo ' '
  echo 'RULES environment variable with path to Nix file specifying recipient public keys.'
  echo "Defaults to './secrets.nix'"
}

test $# -eq 0 && (show_help && exit 1)

REKEY=0
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
    *)
      show_help
      exit 1
      ;;
  esac
done

RULES=''${RULES:-./secrets.nix}

function cleanup {
    if [ ! -z ''${CLEARTEXT_DIR+x} ]
    then
        rm -rf "$CLEARTEXT_DIR"
    fi
    if [ ! -z ''${REENCRYPTED_DIR+x} ]
    then
        rm -rf "$REENCRYPTED_DIR"
    fi
}
trap "cleanup" 0 2 3 15

function edit {
    FILE=$1
    KEYS=$((nix-instantiate --eval -E "(let rules = import $RULES; in builtins.concatStringsSep \"\n\" rules.\"$FILE\".public_keys)" | sed 's/"//g' | sed 's/\\n/\n/g') || exit 1)

    if [ -z "$KEYS" ]
    then
        >&2 echo "There is no rule for $FILE in $RULES."
        exit 1
    fi

    CLEARTEXT_DIR=$(mktemp -d)
    CLEARTEXT_FILE="$CLEARTEXT_DIR/$(basename "$FILE")"

    if [ -f "$FILE" ]
    then
        DECRYPT=("''${DEFAULT_DECRYPT[@]}")
        while IFS= read -r key
        do
            DECRYPT+=(--identity "$key")
        done <<<"$((find ~/.ssh -maxdepth 1 -type f -not -name "*pub" -not -name "config" -not -name "authorized_keys" -not -name "known_hosts") || exit 1)"
        DECRYPT+=(-o "$CLEARTEXT_FILE" "$FILE")
        ${age}/bin/age "''${DECRYPT[@]}" || exit 1
        cp "$CLEARTEXT_FILE" "$CLEARTEXT_FILE.before"
    fi

    $EDITOR "$CLEARTEXT_FILE"

    if [ ! -f "$CLEARTEXT_FILE" ]
    then
      echo "$FILE wasn't created."
      return
    fi
    [ -f "$FILE" ] && [ "$EDITOR" != ":" ] && diff "$CLEARTEXT_FILE.before" "$CLEARTEXT_FILE" 1>/dev/null && echo "$FILE wasn't changed, skipping re-encryption." && return

    ENCRYPT=()
    while IFS= read -r key
    do
        ENCRYPT+=(--recipient "$key")
    done <<< "$KEYS"

    REENCRYPTED_DIR=$(mktemp -d)
    REENCRYPTED_FILE="$REENCRYPTED_DIR/$(basename "$FILE")"

    ENCRYPT+=(-o "$REENCRYPTED_FILE")

    ${age}/bin/age "''${ENCRYPT[@]}" <"$CLEARTEXT_FILE" || exit 1

    mv -f "$REENCRYPTED_FILE" "$1"
}

function rekey {
    FILES=$((nix-instantiate --eval -E "(let rules = import $RULES; in builtins.concatStringsSep \"\n\" (builtins.attrNames rules))"  | sed 's/"//g' | sed 's/\\n/\n/g') || exit 1)

    for FILE in $FILES
    do
        echo "rekeying $FILE..."
        EDITOR=: edit "$FILE"
        cleanup
    done
}

[ $REKEY -eq 1 ] && rekey && exit 0
edit "$FILE" && cleanup && exit 0
''
