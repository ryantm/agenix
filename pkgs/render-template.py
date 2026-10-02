"""Expand explicitly listed secret placeholders without interpreting their contents."""

import json
from pathlib import Path
import re
import sys


def render(template, stage, manifest):
    replacements = {}
    for name in manifest["secrets"]:
        value = Path(f"{stage}/{name}").read_bytes()
        if manifest["trimFinalNewline"] and value.endswith(b"\n"):
            value = value[:-1]
            if value.endswith(b"\r"):
                value = value[:-1]
        replacements[f"@{name}@".encode()] = value
    if not replacements:
        return template
    pattern = re.compile(b"|".join(re.escape(key) for key in sorted(replacements, key=len, reverse=True)))
    return pattern.sub(lambda match: replacements[match[0]], template)


if __name__ == "__main__":
    try:
        template_path, stage, manifest_path = sys.argv[1:]
        manifest = json.loads(Path(manifest_path).read_text())
        sys.stdout.buffer.write(render(Path(template_path).read_bytes(), stage, manifest))
    except (OSError, ValueError) as error:
        print(f"agenix: cannot render template: {error}", file=sys.stderr)
        sys.exit(1)
