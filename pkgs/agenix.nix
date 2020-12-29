{writeShellScriptBin, runtimeShell, pkgs} :
let
  rage = pkgs.callPackage ./rage.nix {};
  ageBin = "${rage}/bin/rage";
in
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
  echo '-v, --verbose             verbose output'
  echo ' '
  echo 'FILE an age-encrypted file'
  echo ' '
  echo 'PRIVATE_KEY a path to a private SSH key used to decrypt file'
  echo ' '
  echo 'EDITOR environment variable of editor to use when editing FILE'
  echo ' '
  echo 'RULES environment variable with path to Nix file specifying recipient public keys.'
  echo "Defaults to './secrets.nix'"
  echo ' '
  echo "age binary path: ${ageBin}"
  echo "age version: $(${ageBin} --version)"
}

test $# -eq 0 && (show_help && exit 1)

REKEY=0
GIT_DIFF_TEXTCONV=0
GIT_FILTER_SMUDGE=0
GIT_FILTER_CLEAN=0
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
    --git-diff-textconv)
      shift
      if test $# -gt 0; then
        export FILE=$1
      else
        echo "no FILE specified"
        exit 1
      fi
      shift
      GIT_DIFF_TEXTCONV=1
      ;;
    --git-filter-smudge)
      shift
      GIT_FILTER_SMUDGE=1
      ;;
    --git-filter-clean)
      shift
      GIT_FILTER_CLEAN=1
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

function _keys {
    KEYS=$((nix-instantiate --eval -E "(let rules = import $RULES; in builtins.concatStringsSep \"\n\" rules.\"$FILE\".publicKeys)" | sed 's/"//g' | sed 's/\\n/\n/g') || exit 1)

    if [ -z "$KEYS" ]
    then
        >&2 echo "There is no rule for $FILE in $RULES."
        exit 1
    fi
}

function _decrypt_args {
    DECRYPT=("''${DEFAULT_DECRYPT[@]}")
    if [ -f "$HOME/.ssh/id_rsa" ]; then
        DECRYPT+=(--identity "$HOME/.ssh/id_rsa")
    fi
    if [ -f "$HOME/.ssh/id_ed25519" ]; then
        DECRYPT+=(--identity "$HOME/.ssh/id_ed25519")
    fi
    if [[ "''${DECRYPT[*]}" != *"--identity"* ]]; then
      echo "No identity found to decrypt $FILE. Try adding an SSH key at $HOME/.ssh/id_rsa or $HOME/.ssh/id_ed25519 or using the --identity flag to specify a file."
      exit 1
    fi
}

function _encrypt_args {
    ENCRYPT=()
    while IFS= read -r key
    do
        ENCRYPT+=(--recipient "$key")
    done <<< "$KEYS"
}

function git_diff_textconv {
    FILE=$1
    _decrypt_args
        DECRYPT+=("$FILE")
    ${ageBin} "''${DECRYPT[@]}" || exit 1
}
function git_filter_smudge {
    _decrypt_args
    ${ageBin} "''${DECRYPT[@]}" || exit 1
}
function git_filter_clean {
    _encrypt_args
    ${ageBin} "''${ENCRYPT[@]}" || exit 1
}

function edit {
    FILE=$1
    _keys

    CLEARTEXT_DIR=$(mktemp -d)
    CLEARTEXT_FILE="$CLEARTEXT_DIR/$(basename "$FILE")"

    if [ -f "$FILE" ]
    then
        _decrypt_args
        DECRYPT+=(-o "$CLEARTEXT_FILE" "$FILE")
        ${ageBin} "''${DECRYPT[@]}" || exit 1
        cp "$CLEARTEXT_FILE" "$CLEARTEXT_FILE.before"
    fi

    $EDITOR "$CLEARTEXT_FILE"

    if [ ! -f "$CLEARTEXT_FILE" ]
    then
      echo "$FILE wasn't created."
      return
    fi
    [ -f "$FILE" ] && [ "$EDITOR" != ":" ] && diff "$CLEARTEXT_FILE.before" "$CLEARTEXT_FILE" 1>/dev/null && echo "$FILE wasn't changed, skipping re-encryption." && return

    _encrypt_args

    REENCRYPTED_DIR=$(mktemp -d)
    REENCRYPTED_FILE="$REENCRYPTED_DIR/$(basename "$FILE")"

    ENCRYPT+=(-o "$REENCRYPTED_FILE")

    ${ageBin} "''${ENCRYPT[@]}" <"$CLEARTEXT_FILE" || exit 1

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
[ $GIT_DIFF_TEXTCONV -eq 1 ] && git_diff_textconv && exit 0
[ $GIT_FILTER_SMUDGE -eq 1 ] && git_filter_smudge && exit 0
[ $GIT_FILTER_CLEAN -eq 1 ] && git_filter_clean && exit 0
edit "$FILE" && cleanup && exit 0
''
