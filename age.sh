#! /usr/bin/env nix-shell
#! nix-shell -i bash -p age yq-go
set -euxo pipefail

RULES=example.yaml

function cleanup {
    if [ ! -z ${CLEARTEXT_DIR+x} ]
    then
        rm -rf "$CLEARTEXT_DIR"
    fi
    if [ ! -z ${REENCRYPTED_DIR+x} ]
    then
        rm -rf "$REENCRYPTED_DIR"
    fi
}
trap "cleanup" 0 2 3 15

function ageEdit {
    FILE=$1
    KEYS=$(yq r "$RULES" "secrets.(name==$FILE).public_keys.**")
    if [ -z "$KEYS" ]
    then
        >&2 echo "There is no rule for $FILE in $RULES."
        exit 1
    fi

    CLEARTEXT_DIR=$(mktemp -d)
    CLEARTEXT_FILE="$CLEARTEXT_DIR/$(basename "$FILE")"


    if [ -f "$FILE" ]
    then
        DECRYPT=(--decrypt)
        while IFS= read -r key
        do
            DECRYPT+=(--identity "$key")
        done <<<$(find ~/.ssh -maxdepth 1 -type f -not -name "*pub" -not -name "config" -not -name "authorized_keys" -not -name "known_hosts")
        DECRYPT+=(-o "$CLEARTEXT_FILE" "$FILE")
        age "${DECRYPT[@]}"
    fi

    $EDITOR "$CLEARTEXT_FILE"

    ENCRYPT=()
    while IFS= read -r key
    do
        echo "$key"
        ENCRYPT+=(--recipient "$key")
    done <<< "$KEYS"

    REENCRYPTED_DIR=$(mktemp -d)
    REENCRYPTED_FILE="$REENCRYPTED_DIR/$(basename "$FILE")"

    ENCRYPT+=(-o "$REENCRYPTED_FILE")

    cat "$CLEARTEXT_FILE" | age "${ENCRYPT[@]}"

    mv -f "$REENCRYPTED_FILE" "$1"
}

function rekey {
    FILES=$(yq r "$RULES" "secrets.*.name")
    for FILE in $FILES
    do
        EDITOR=echo ageEdit $FILE
    done
}
