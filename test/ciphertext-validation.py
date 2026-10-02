import base64
import pathlib
import subprocess
import sys

validator, age, examples, public_key = sys.argv[1:]
examples = pathlib.Path(examples)


def check(data, valid):
    path = pathlib.Path("candidate.age")
    path.write_bytes(data)
    result = subprocess.run([validator, str(path)], capture_output=True, check=False)
    assert (result.returncode == 0) == valid, result.stderr
    assert result.stdout == b"", result.stdout
    assert b"private-marker-must-not-appear" not in result.stderr, result.stderr


raw = (examples / "secret1.age").read_bytes()
armored = (examples / "armored-secret.age").read_bytes()
check(raw, True)
check(armored, True)
check(b"\n \t\n" + armored.replace(b"\n", b"\r\n") + b" \n", True)

footer = raw.index(b"\n--- ") + 1
payload = raw.index(b"\n", footer) + 1
for malformed in (
    b"",
    b"private-marker-must-not-appear\n",
    b"age-encryption.org/v1\n",
    raw.replace(b"-> ssh-ed25519 ", b"-> \x00 ", 1),
    raw[:footer] + b"--- invalid-mac\n" + raw[payload:],
    raw[:payload],
    raw[:payload + 16],
    raw[:payload + 31],
    armored.replace(b"-----END AGE ENCRYPTED FILE-----", b"bad footer"),
    armored + b"private-marker-must-not-appear",
    b"-----BEGIN AGE ENCRYPTED FILE-----\n!!!!\n-----END AGE ENCRYPTED FILE-----\n",
):
    check(malformed, False)

for size in (0, 1, 65520, 65535, 65536, 65537, 131072):
    ciphertext = subprocess.run(
        [age, "--encrypt", "-R", public_key],
        input=b"x" * size, capture_output=True, check=True,
    ).stdout
    check(ciphertext, True)
    encoded = base64.b64encode(ciphertext)
    lines = [encoded[i:i + 64] for i in range(0, len(encoded), 64)]
    check(b"-----BEGIN AGE ENCRYPTED FILE-----\n" + b"\n".join(lines)
          + b"\n-----END AGE ENCRYPTED FILE-----\n", True)

# Without an identity, format checking cannot detect an altered authentication tag.
check(raw[:-1] + bytes([raw[-1] ^ 1]), True)
