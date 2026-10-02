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
sed 's/"secret2.age".publicKeys = \[ user1 \];/"secret2.age".publicKeys = [ system1 ];/' secrets.nix > changed-rules.nix
if AGENIX_RULES=changed-rules.nix "$agenix" --check > check-report; then
  fail 'recipient check accepted changed rules'
fi
grep -q '^✗ secret2.age$' check-report
grep -q '^  missing: ssh-ed25519 ' check-report
grep -q '^  extra: ssh-ed25519 ' check-report

# Filename normalization, edit, and discovery of old and new rules files.
[[ $(decrypt ./secret1.age 2>/dev/null) == hello ]]
EDITOR=: "$agenix" -e ./secret1.age -i "$HOME/.ssh/id_ed25519"
[[ $(decrypt secret1.age 2>/dev/null) == hello ]]
output=$(env -u AGENIX_RULES -u RULES "$agenix" -d secret1.age 2>&1)
has "$output" 'automatic discovery of secrets.nix are deprecated'
has "$output" hello
output=$(RULES=secrets.nix "$agenix" -d secret1.age 2>&1)
has "$output" 'RULES and automatic discovery of secrets.nix are deprecated'
output=$(AGENIX_RULES=secrets.nix "$agenix" -d secret1.age 2>&1)
lacks "$output" deprecated
cp secrets.nix agenix-rules.nix
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

EDITOR=: "$agenix" -e passwordfile-user1.age </dev/null
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
