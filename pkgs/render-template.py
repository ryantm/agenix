"""Expand explicitly listed secret placeholders without interpreting their contents."""

import json
from pathlib import Path
import re
import shlex
import sys


def environment_values(stage, names):
    values = {}
    for name in names:
        try:
            lines = Path(f"{stage}/{name}").read_text(encoding="utf-8").splitlines()
        except UnicodeError:
            raise ValueError(f"environment input {name!r} is not UTF-8") from None
        for number, line in enumerate(lines, 1):
            try:
                words = shlex.split(line, comments=True, posix=True)
            except ValueError:
                raise ValueError(f"invalid environment assignment in {name!r} at line {number}") from None
            if not words:
                continue
            if words[0] == "export":
                words = words[1:]
            if len(words) != 1 or not re.fullmatch(r"[A-Za-z_][A-Za-z0-9_]*=.*", words[0]):
                raise ValueError(f"invalid environment assignment in {name!r} at line {number}")
            key, value = words[0].split("=", 1)
            values[key.encode()] = value.encode()
    return values


def json_string(value):
    try:
        return json.dumps(value.decode("utf-8"), ensure_ascii=False)[1:-1].encode()
    except UnicodeError:
        raise ValueError("JSON substitutions must be UTF-8") from None


def reject_json_constant(_value):
    raise ValueError("non-finite JSON number")


def render(template, stage, manifest):
    replacements = {}
    for name in manifest["secrets"]:
        value = Path(f"{stage}/{name}").read_bytes()
        if manifest["trimFinalNewline"] and value.endswith(b"\n"):
            value = value[:-1]
            if value.endswith(b"\r"):
                value = value[:-1]
        replacements[f"@{name}@".encode()] = value
    environment = environment_values(stage, manifest.get("environmentFiles", []))
    patterns = [re.escape(key) for key in sorted(replacements, key=len, reverse=True)]
    if manifest.get("environmentFiles"):
        patterns.append(rb"\$(?:\{([A-Za-z_][A-Za-z0-9_]*)\}|([A-Za-z_][A-Za-z0-9_]*))")

    def substitute(match):
        if match[0] in replacements:
            value = replacements[match[0]]
        else:
            name = match[1] or match[2]
            if name not in environment:
                raise ValueError(f"undefined template variable {name.decode()!r}")
            value = environment[name]
        return json_string(value) if manifest.get("format", "text") == "json" else value

    result = re.sub(b"|".join(patterns), substitute, template) if patterns else template
    if manifest.get("format", "text") == "json":
        try:
            json.loads(result.decode("utf-8"), parse_constant=reject_json_constant)
        except (ValueError, UnicodeError):
            raise ValueError("rendered template is not valid UTF-8 JSON") from None
    return result


if __name__ == "__main__":
    try:
        template_path, stage, manifest_path = sys.argv[1:]
        manifest = json.loads(Path(manifest_path).read_text())
        sys.stdout.buffer.write(render(Path(template_path).read_bytes(), stage, manifest))
    except (OSError, ValueError) as error:
        print(f"agenix: cannot render template: {error}", file=sys.stderr)
        sys.exit(1)
