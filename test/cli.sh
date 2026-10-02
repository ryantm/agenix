#!/usr/bin/env bash
set -euo pipefail

agenix=$1
examples=$2
keys=$3
one_way_rules=$4
test_tmp=$(mktemp -d)
trap 'rm -rf "$test_tmp"' EXIT
export HOME="$test_tmp/home"
export NIX_STORE_DIR="$test_tmp/nix/store"
export NIX_STATE_DIR="$test_tmp/nix/var"
mkdir -p "$HOME/.ssh" "$NIX_STORE_DIR" "$NIX_STATE_DIR"
cp -r "$examples" "$HOME/secrets"
chmod -R u+rw "$HOME/secrets"
install -m 0600 "$keys/user1" "$HOME/.ssh/id_ed25519"
install -m 0644 "$keys/user1.pub" "$HOME/.ssh/id_ed25519.pub"
cd "$HOME/secrets"

fail() { printf '%s\n' "$*" >&2; exit 1; }
has() { [[ $1 == *"$2"* ]] || fail "expected '$2' in: $1"; }
lacks() { [[ $1 != *"$2"* ]] || fail "unexpected '$2' in: $1"; }
decrypt() { "$agenix" -d "$1" "${@:2}"; }
hash() { sha256sum "$1" | cut -d ' ' -f 1; }

[[ $(decrypt secret1.age 2>/dev/null) == hello ]] || fail 'fixture decryption failed'
"$agenix" --check
sed 's/"secret2.age".publicKeys = \[ user1 \];/"secret2.age".publicKeys = [ system1 ];/' agenix-rules.nix > changed-rules.nix
if AGENIX_RULES=changed-rules.nix "$agenix" --check > check-report; then
  fail 'recipient check accepted changed rules'
fi
grep -q '^✗ secret2.age$' check-report
grep -q '^  missing: ssh-ed25519 ' check-report
# Even though the old key remains literal in changed-rules.nix, show its tag.
grep -Eq '^  extra: ssh-ed25519 [A-Za-z0-9+/]{6}$' check-report

# Filename normalization, edit, and discovery of old and new rules files.
[[ $(decrypt ./secret1.age 2>/dev/null) == hello ]]
EDITOR=: "$agenix" -e ./secret1.age -i "$HOME/.ssh/id_ed25519"
[[ $(decrypt secret1.age 2>/dev/null) == hello ]]
cp agenix-rules.nix secrets.nix
mv agenix-rules.nix agenix-rules.nix.hidden
output=$(env -u AGENIX_RULES -u RULES "$agenix" -d secret1.age 2>&1)
has "$output" 'automatic discovery of secrets.nix are deprecated'
has "$output" hello
output=$(RULES=secrets.nix "$agenix" -d secret1.age 2>&1)
has "$output" 'RULES and automatic discovery of secrets.nix are deprecated'
output=$(AGENIX_RULES=secrets.nix "$agenix" -d secret1.age 2>&1)
lacks "$output" deprecated
mv agenix-rules.nix.hidden agenix-rules.nix
output=$(env -u AGENIX_RULES -u RULES "$agenix" -d secret1.age 2>&1)
lacks "$output" deprecated
output=$(RULES=agenix-rules.nix "$agenix" -d secret1.age 2>&1)
has "$output" deprecated
output=$(RULES=secrets.nix AGENIX_RULES=agenix-rules.nix "$agenix" -d secret1.age 2>&1)
lacks "$output" deprecated
if AGENIX_RULES=missing.nix decrypt secret1.age > missing-output 2>&1; then
  fail 'missing explicit rules file was accepted'
fi
mkdir nested
output=$(cd nested && env -u AGENIX_RULES -u RULES "$agenix" -d secret1.age 2>&1)
has "$output" hello
lacks "$output" deprecated
mv agenix-rules.nix agenix-rules.nix.hidden
if (cd nested && env -u AGENIX_RULES -u RULES "$agenix" -d secret1.age) > missing-output 2>&1; then
  fail 'parent secrets.nix was discovered'
fi
grep -q 'needs a rules file' missing-output
mv agenix-rules.nix.hidden agenix-rules.nix
cp secrets.nix secret1.age nested/
output=$(cd nested && env -u AGENIX_RULES -u RULES "$agenix" -d secret1.age 2>&1)
has "$output" 'automatic discovery of secrets.nix are deprecated'

# Rekey must write beside the discovered rules, even from a child directory.
before=$(hash passwordfile-user1.age)
mkdir nested-rekey
ln -s "$HOME/.ssh/id_ed25519" nested-rekey/identity
output=$(cd nested-rekey && "$agenix" -r -i identity 2>&1)
lacks "$output" "wasn't created"
[[ $(hash passwordfile-user1.age) != "$before" ]]
[[ ! -e nested-rekey/passwordfile-user1.age ]]
output=$(cd nested-rekey && AGENIX_RULES=../agenix-rules.nix "$agenix" -d secret1.age 2>&1)
has "$output" hello
lacks "$output" deprecated
before=$(hash passwordfile-user1.age)
"$agenix" -r -i "$HOME/.ssh/id_ed25519"
[[ $(hash passwordfile-user1.age) != "$before" ]]

selected_before=$(hash ./-leading-hyphen-filename.age)
unselected_before=$(hash secret1.age)
"$agenix" --rekey-file ./-leading-hyphen-filename.age -i "$HOME/.ssh/id_ed25519"
[[ $(hash ./-leading-hyphen-filename.age) != "$selected_before" ]]
[[ $(hash secret1.age) == "$unselected_before" ]]

# A recipient filter selects by the current rules and keeps other files intact.
selected_before=$(hash secret1.age)
unselected_before=$(hash secret2.age)
armored_before=$(hash armored-secret.age)
recipient=$(cut -d ' ' -f 1,2 "$keys/system1.pub")
"$agenix" --rekey "$recipient" -i "$HOME/.ssh/id_ed25519"
[[ $(hash secret1.age) != "$selected_before" ]]
[[ $(hash secret2.age) == "$unselected_before" ]]
[[ $(hash armored-secret.age) == "$armored_before" ]]
[[ $(decrypt secret1.age 2>/dev/null) == hello ]]

# Missing filters must fail without changing files, including strings that
# would become Nix code if interpolated into the expression.
selected_before=$(hash secret1.age)
for recipient in '' 'unknown-recipient' '"; builtins.abort "injected'; do
  if "$agenix" -r "$recipient" > rekey-output 2>&1; then
    fail 'invalid recipient filter succeeded'
  fi
  [[ $(hash secret1.age) == "$selected_before" ]]
done
grep -q 'No secrets in the rules match PUBLIC_KEY' rekey-output

EDITOR=: "$agenix" -e passwordfile-user1.age </dev/null
# Local rules are intentionally impure, even if nix.conf defaults to pure eval.
NIX_CONFIG='pure-eval = true' "$agenix" --check
[[ $(NIX_CONFIG='pure-eval = true' decrypt secret1.age) == hello ]]
NIX_CONFIG='pure-eval = true' EDITOR=: "$agenix" -e secret1.age
NIX_CONFIG='pure-eval = true' "$agenix" -r </dev/null
[[ $(decrypt secret1.age) == hello ]]

printf 'bogus\n' > "$HOME/.ssh/id_rsa"
before=$(hash passwordfile-user1.age)
if EDITOR=: "$agenix" -e passwordfile-user1.age </dev/null; then
  fail 'edit with bogus identity succeeded'
fi
[[ $(hash passwordfile-user1.age) == "$before" ]]
EDITOR=: "$agenix" -e passwordfile-user1.age -i "$HOME/.ssh/id_ed25519" </dev/null
rm "$HOME/.ssh/id_rsa"
printf 'secret1234\n' | "$agenix" -e passwordfile-user1.age
[[ $(decrypt passwordfile-user1.age 2>/dev/null) == secret1234 ]]
if grep -r -q secret1234 "$test_tmp"; then
  fail 'plaintext remained in the test directory'
fi

# A user with no recipient identity can replace a secret, but cannot decrypt it.
mkdir "$test_tmp/without-identity" "$test_tmp/one-way"
cp "$one_way_rules" "$test_tmp/one-way/agenix-rules.nix"
chmod u+w "$test_tmp/one-way/agenix-rules.nix"
cd "$test_tmp/one-way"
printf 'eye1234\n' | HOME="$test_tmp/without-identity" "$agenix" -e one-way.age
if HOME="$test_tmp/without-identity" decrypt one-way.age </dev/null; then
  fail 'one-way secret decrypted without identity'
fi
[[ $(decrypt one-way.age -i "$keys/system1" </dev/null) == eye1234 ]]
before=$(hash one-way.age)
if HOME="$test_tmp/without-identity" EDITOR=: "$agenix" -e one-way.age </dev/null; then
  fail 'edit without identity succeeded'
fi
[[ $(hash one-way.age) == "$before" ]]
printf 'nose1234\n' | HOME="$test_tmp/without-identity" "$agenix" -e one-way.age
[[ $(decrypt one-way.age -i "$keys/system1" </dev/null) == nose1234 ]]
before=$(hash one-way.age)
if HOME="$test_tmp/without-identity" "$agenix" -r </dev/null; then
  fail 'rekey without identity succeeded'
fi
[[ $(hash one-way.age) == "$before" ]]
"$agenix" -r -i "$keys/system1" </dev/null
[[ $(hash one-way.age) != "$before" ]]
[[ $(decrypt one-way.age -i "$keys/system1" </dev/null) == nose1234 ]]

# Model the discovery command with public SSH fixtures so real age verifies
# decryption. Physical YubiKey access and the plugin protocol are separate.
(
  mkdir "$test_tmp/yubikey-bin" "$test_tmp/yubikey-tmp"
  export TMPDIR="$test_tmp/yubikey-tmp"
  export PATH="$test_tmp/yubikey-bin:$PATH"
  export HOME="$test_tmp/without-identity"
  export YUBIKEY_TEST_KEY="$keys/system1"
  export YUBIKEY_TEST_LOG="$test_tmp/yubikey-calls"
  export YUBIKEY_TEST_MODE=valid
  printf '#!%s\n' "$BASH" > "$test_tmp/yubikey-bin/age-plugin-yubikey"
  cat >> "$test_tmp/yubikey-bin/age-plugin-yubikey" <<'PLUGIN'
set -euo pipefail
[[ $# -eq 1 && $1 == --identity ]]
printf 'discovered\n' >> "$YUBIKEY_TEST_LOG"
case "$YUBIKEY_TEST_MODE" in
  valid) cat "$YUBIKEY_TEST_KEY" ;;
  empty) exit 0 ;;
  failed) cat "$YUBIKEY_TEST_KEY"; exit 17 ;;
  invalid) printf 'invalid identity\n' ;;
esac
PLUGIN
  chmod +x "$test_tmp/yubikey-bin/age-plugin-yubikey"
  cp agenix-rules.nix original-rules.nix
  printf '%s\n' 'let rules = import ./original-rules.nix; in rules // { "second.age" = rules."one-way.age"; }' > agenix-rules.nix
  cp one-way.age second.age

  [[ $("$agenix" --yubikey -d one-way.age) == nose1234 ]]
  [[ -z $(find "$TMPDIR" -mindepth 1 -print) ]]
  # Explicit file identities can supplement discovered identities.
  [[ $("$agenix" --yubikey -i "$keys/user1" -d one-way.age) == nose1234 ]]
  EDITOR=: "$agenix" --yubikey -e one-way.age </dev/null
  : > "$YUBIKEY_TEST_LOG"
  "$agenix" --yubikey -r </dev/null
  [[ $(wc -l < "$YUBIKEY_TEST_LOG") -eq 1 ]]
  [[ -z $(find "$TMPDIR" -mindepth 1 -print) ]]
  [[ $("$agenix" --yubikey -d second.age) == nose1234 ]]

  before=$(hash one-way.age)
  for YUBIKEY_TEST_MODE in empty failed invalid; do
    export YUBIKEY_TEST_MODE
    if "$agenix" --yubikey --rekey-file one-way.age > "$test_tmp/yubikey-error" 2>&1; then
      fail "YubiKey discovery accepted $YUBIKEY_TEST_MODE output"
    fi
    [[ $(hash one-way.age) == "$before" ]]
    [[ -z $(find "$TMPDIR" -mindepth 1 -print) ]]
  done

  # No decryption means no hardware discovery, even with the flag enabled.
  : > "$YUBIKEY_TEST_LOG"
  YUBIKEY_TEST_MODE=failed "$agenix" --yubikey --check
  printf replacement | YUBIKEY_TEST_MODE=failed "$agenix" --yubikey -e one-way.age
  [[ ! -s $YUBIKEY_TEST_LOG ]]
  [[ $(decrypt one-way.age -i "$keys/system1") == replacement ]]
  mv "$test_tmp/yubikey-bin/age-plugin-yubikey" "$test_tmp/yubikey-bin/disabled-plugin"
  if "$agenix" --yubikey -d one-way.age > "$test_tmp/yubikey-error" 2>&1; then
    fail 'missing YubiKey plugin was accepted'
  fi
  grep -q -- '--yubikey requires age-plugin-yubikey on PATH.' "$test_tmp/yubikey-error"
  [[ -z $(find "$TMPDIR" -mindepth 1 -print) ]]
)
