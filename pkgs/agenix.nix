{writeShellScriptBin, runtimeShell, age} :
writeShellScriptBin "agenix" ''
set -euo pipefail

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
    KEYS=$(nix-instantiate --eval -E "(let rules = import $RULES; in builtins.concatStringsSep \"\n\" rules.\"$FILE\".public_keys)" | sed 's/"//g' | sed 's/\\n/\n/g')

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
        done <<<$(find ~/.ssh -maxdepth 1 -type f -not -name "*pub" -not -name "config" -not -name "authorized_keys" -not -name "known_hosts")
        DECRYPT+=(-o "$CLEARTEXT_FILE" "$FILE")
        ${age}/bin/age "''${DECRYPT[@]}"
    fi

    $EDITOR "$CLEARTEXT_FILE"

    ENCRYPT=()
    while IFS= read -r key
    do
        ENCRYPT+=(--recipient "$key")
    done <<< "$KEYS"

    REENCRYPTED_DIR=$(mktemp -d)
    REENCRYPTED_FILE="$REENCRYPTED_DIR/$(basename "$FILE")"

    ENCRYPT+=(-o "$REENCRYPTED_FILE")

    cat "$CLEARTEXT_FILE" | ${age}/bin/age "''${ENCRYPT[@]}"

    mv -f "$REENCRYPTED_FILE" "$1"
}

function rekey {
    echo "rekeying..."
    FILES=$(nix-instantiate --eval -E "(let rules = import $RULES; in builtins.concatStringsSep \"\n\" (builtins.attrNames rules))"  | sed 's/"//g' | sed 's/\\n/\n/g')

    for FILE in $FILES
    do
        EDITOR=: edit $FILE
    done
}

[ $REKEY -eq 1 ] && rekey && exit 0
edit $FILE && exit 0
''
