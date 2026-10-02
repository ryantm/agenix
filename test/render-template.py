import importlib.util
import json
from pathlib import Path
import subprocess
import sys
import tempfile
import unittest

renderer_path = Path(sys.argv.pop(1))
spec = importlib.util.spec_from_file_location("renderer", renderer_path)
renderer = importlib.util.module_from_spec(spec)
spec.loader.exec_module(renderer)


class TemplateTest(unittest.TestCase):
    def setUp(self):
        self.directory = tempfile.TemporaryDirectory()
        self.addCleanup(self.directory.cleanup)
        self.stage = Path(self.directory.name)

    def expand(self, template, values, trim=True):
        for name, value in values.items():
            (self.stage / name).write_bytes(value)
        return renderer.render(template, self.stage, {"secrets": list(values), "trimFinalNewline": trim})

    def test_literal_single_pass(self):
        value = b"$() `commands` \\ \" ' @other@\nsecond line\n"
        self.assertEqual(
            self.expand(b"@key[.*]@ / @other@ / @unlisted@", {"key[.*]": value, "other": b"end"}),
            value[:-1] + b" / end / @unlisted@",
        )

    def test_newline_policy(self):
        self.assertEqual(self.expand(b"@a@,@b@,@c@", {"a": b"abc", "b": b"x\r\n", "c": b"y\n\n"}), b"abc,x,y\n")

    def test_exact_binary_bytes(self):
        value = b"binary\0\xff\r\n"
        self.assertEqual(self.expand(b"before:@a@:after", {"a": value}, trim=False), b"before:" + value + b":after")

    def test_environment_assignments_and_single_pass(self):
        (self.stage / "first").write_bytes(
            b"# comment\nA=one\nexport B='two words'\nEMPTY=\nHASH='a#b'\n"
            b"LITERAL='$(touch /tmp/agenix-env-pwned) `command` $A @other@'\n"
        )
        (self.stage / "second").write_bytes(b'A="last=value" # comment\n')
        manifest = {"secrets": [], "trimFinalNewline": True, "environmentFiles": ["first", "second"]}
        result = renderer.render(b"$A/${B}/${EMPTY}/$HASH/$LITERAL", self.stage, manifest)
        self.assertEqual(result, b"last=value/two words//a#b/$(touch /tmp/agenix-env-pwned) `command` $A @other@")
        self.assertEqual(self.expand(b"$PATH ${HOME}", {}), b"$PATH ${HOME}")

    def test_json_escaping_for_file_and_environment_values(self):
        value = b'quote " slash \\ newline\nnull\0'
        (self.stage / "value").write_bytes(value)
        (self.stage / "env").write_bytes(b"TOKEN='quote \" slash \\ $NOT_EXPANDED'\n")
        manifest = {"secrets": ["value"], "trimFinalNewline": False, "environmentFiles": ["env"], "format": "json"}
        result = renderer.render(b'{"file":"@value@","env":"${TOKEN}"}', self.stage, manifest)
        self.assertEqual(json.loads(result), {"file": value.decode(), "env": 'quote " slash \\ $NOT_EXPANDED'})

    def test_invalid_environment_never_emits_its_contents(self):
        for value in [b"TOKEN='private-value", b"command private-value", b"1INVALID=private-value", b"TOKEN=\xff"]:
            with self.subTest(value=value):
                (self.stage / "env").write_bytes(value)
                with self.assertRaises(ValueError) as raised:
                    renderer.render(b"$TOKEN", self.stage, {"secrets": [], "environmentFiles": ["env"]})
                self.assertNotIn("private-value", str(raised.exception))

    def test_missing_variable_and_invalid_json_fail(self):
        (self.stage / "env").write_bytes(b"PRESENT=value\n")
        manifest = {"secrets": [], "environmentFiles": ["env"]}
        with self.assertRaisesRegex(ValueError, "undefined template variable"):
            renderer.render(b"$MISSING", self.stage, manifest)
        for template in [b'{"key": $PRESENT}', b'{"key": NaN}', b'{"key": Infinity}']:
            with self.assertRaisesRegex(ValueError, "not valid UTF-8 JSON"):
                renderer.render(template, self.stage, {**manifest, "format": "json"})
        (self.stage / "binary").write_bytes(b"\xff")
        with self.assertRaisesRegex(ValueError, "JSON substitutions must be UTF-8"):
            renderer.render(b'"@binary@"', self.stage, {"secrets": ["binary"], "trimFinalNewline": False, "format": "json"})

    def test_undefined_variable_emits_no_partial_output(self):
        template = self.stage / "template"
        manifest = self.stage / "manifest.json"
        template.write_bytes(b"$PRESENT $MISSING")
        (self.stage / "env").write_bytes(b"PRESENT=private-value\n")
        manifest.write_text(json.dumps({"secrets": [], "environmentFiles": ["env"]}))
        result = subprocess.run([sys.executable, str(renderer_path), str(template), str(self.stage), str(manifest)], capture_output=True)
        self.assertNotEqual(result.returncode, 0)
        self.assertEqual(result.stdout, b"")
        self.assertNotIn(b"private-value", result.stderr)

    def test_missing_input_emits_no_partial_output(self):
        template = self.stage / "template"
        manifest = self.stage / "manifest.json"
        template.write_bytes(b"@present@ @missing@")
        (self.stage / "present").write_bytes(b"secret-value")
        manifest.write_text(json.dumps({"secrets": ["present", "missing"], "trimFinalNewline": True}))
        result = subprocess.run([sys.executable, str(renderer_path), str(template), str(self.stage), str(manifest)], capture_output=True)
        self.assertNotEqual(result.returncode, 0)
        self.assertEqual(result.stdout, b"")
        self.assertNotIn(b"secret-value", result.stderr)


unittest.main()
