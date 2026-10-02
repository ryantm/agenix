#!/usr/bin/env bash
set -euo pipefail
agenix=$1
identity=$2/user1
export HOME="$TMPDIR/home"
export NIX_STORE_DIR="$TMPDIR/store"
export NIX_STATE_DIR="$TMPDIR/state"
export NIX_EVAL_COUNT="$TMPDIR/evaluations"
mkdir -p "$HOME" "$NIX_STORE_DIR" "$NIX_STATE_DIR" plaintext
export TMPDIR="$PWD/plaintext"
# Exercise the shell/Nix boundary, including directory and file trailing newlines.
mkdir $'project "quotes"\n'
cd $'project "quotes"\n'
export AGENIX_RULES=$'rules "quotes" ${builtins.abort "injected"}.nix\n'
strange=$'dir "quotes"\n/secret\\name ${builtins.abort "injected"}.age\n'
plain='secret with spaces.age'
recipient=$(cut -d ' ' -f 1,2 "$identity.pub")
jq -n --arg strange "$strange" --arg plain "$plain" --arg key "$recipient" \
  '{($strange): {publicKeys: [$key], armor: true}, ($plain): {publicKeys: [$key]}}' > rules.json
printf '%s\n' 'builtins.fromJSON (builtins.readFile ./rules.json)' > "$AGENIX_RULES"
cp "$AGENIX_RULES" valid-rules.nix

once() {
  : > "$NIX_EVAL_COUNT"
  "$@"
  test "$(wc -l < "$NIX_EVAL_COUNT")" -eq 1
}

printf original | once "$agenix" -e "$strange"
printf second | once "$agenix" -e "$plain"
head -n 1 -- "$strange" | grep -qx -- '-----BEGIN AGE ENCRYPTED FILE-----'
once "$agenix" -d "$strange" -i "$identity" > decrypted
test "$(cat decrypted)" = original
once "$agenix" --check
cp -- "$strange" before.age
printf 'must not replace plaintext' | once "$agenix" -r -i "$identity"
! cmp -- before.age "$strange"
test "$("$agenix" -d "$strange" -i "$identity")" = original
test "$("$agenix" -d "$plain" -i "$identity")" = second
once "$agenix" -r "$recipient" -i "$identity" </dev/null
test -z "$(ls -A "$TMPDIR")"
test -z "$(find . -name '.agenix.*')"

# Single-file commands must not evaluate unrelated attributes or rule metadata.
cat > "$AGENIX_RULES" <<'EOF'
(import ./valid-rules.nix) // {
  unrelated = throw "unrelated rule forced";
}
EOF
once "$agenix" -d "$strange" -i "$identity" > decrypted
printf replacement | once "$agenix" -e "$strange"
test "$("$agenix" -d "$strange" -i "$identity")" = replacement
cat > "$AGENIX_RULES" <<'EOF'
builtins.mapAttrs (_: rule: rule // {
  armor = throw "unused armor forced";
  unused = throw "unused field forced";
}) (import ./valid-rules.nix)
EOF
once "$agenix" -d "$strange" -i "$identity" > decrypted
once "$agenix" --check
cp valid-rules.nix "$AGENIX_RULES"

# Recipient selection does not force unused settings or require excluded files.
cat > "$AGENIX_RULES" <<'EOF'
(import ./valid-rules.nix) // {
  excluded = { publicKeys = []; armor = throw "excluded armor forced"; };
}
EOF
once "$agenix" -r "$recipient" -i "$identity" </dev/null
cp valid-rules.nix "$AGENIX_RULES"

# Conflicting or absent operations fail before evaluation or changing ciphertext.
cp -- "$strange" before.age
for operation in -d -e -c -r; do
  : > "$NIX_EVAL_COUNT"
  if "$agenix" -e "$strange" "$operation" "$strange" > error 2>&1; then exit 1; fi
  grep -q 'Select only one' error
  test ! -s "$NIX_EVAL_COUNT"
  cmp -- before.age "$strange"
done
if "$agenix" > error 2>&1; then exit 1; fi
if "$agenix" -e '' > error 2>&1; then exit 1; fi

# A failing editor may modify plaintext, but must not replace the encrypted file.
cat > "$TMPDIR/../failed-editor" <<'EOF'
#!/usr/bin/env bash
printf 'failed editor plaintext' > "$1"
echo 'editor ran' >&2
exit 1
EOF
chmod +x "$TMPDIR/../failed-editor"
export EDITOR="bash $TMPDIR/../failed-editor"
python3 - "$agenix" "$strange" "$identity" <<'PY'
import os
import pty
import subprocess
import sys

master, slave = pty.openpty()
try:
    result = subprocess.run(
        [sys.argv[1], "-e", sys.argv[2], "-i", sys.argv[3]],
        stdin=slave, stdout=subprocess.PIPE, stderr=subprocess.PIPE, timeout=30,
    )
    assert result.returncode != 0, result
    assert b"Editor failed" in result.stderr, result.stderr
    assert b"editor ran" in result.stderr, result.stderr
    unchanged = subprocess.run(
        [sys.argv[1], "-e", sys.argv[2], "-i", sys.argv[3]],
        stdin=slave, stdout=subprocess.PIPE, stderr=subprocess.PIPE, timeout=30,
        env={**os.environ, "EDITOR": "true"},
    )
    assert unchanged.returncode == 0, unchanged.stderr
    assert b"wasn't changed, skipping re-encryption" in unchanged.stderr, unchanged.stderr
finally:
    os.close(master)
    os.close(slave)
PY
cmp -- before.age "$strange"
test -z "$(ls -A "$TMPDIR")"
test -z "$(find . -name '.agenix.*')"
unset EDITOR

# Missing inputs fail; rekey never falls through to an edit or creates a file.
mv -- "$plain" missing.age
if "$agenix" -r -i "$identity" > error 2>&1; then exit 1; fi
grep -q 'does not exist' error
test ! -e "$plain"
test -z "$(ls -A "$TMPDIR")"
if "$agenix" -d "$plain" -i "$identity" > error 2>&1; then exit 1; fi
grep -q 'does not exist' error

# Empty rules are valid for operations over the whole set.
printf '{}\n' > "$AGENIX_RULES"
once "$agenix" --check
once "$agenix" --rekey
