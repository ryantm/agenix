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
