"""Structural gates should catch broken links and stale moved resource paths."""

import importlib.util
from pathlib import Path
import subprocess
import sys
import tempfile
import unittest


TOOL_PATH = Path(__file__).resolve().parents[1] / "tools" / "check_structure.py"
spec = importlib.util.spec_from_file_location("reol_structure", TOOL_PATH)
structure = importlib.util.module_from_spec(spec)
spec.loader.exec_module(structure)


class StructureTests(unittest.TestCase):
    def setUp(self):
        self.directory = tempfile.TemporaryDirectory()
        self.addCleanup(self.directory.cleanup)
        self.root = Path(self.directory.name)

    def write(self, name: str, content: str = "") -> Path:
        path = self.root / name
        path.parent.mkdir(parents=True, exist_ok=True)
        path.write_text(content, encoding="utf-8")
        return path

    def project_entries(self):
        for directory in structure.ROLE_DIRECTORIES:
            (self.root / directory).mkdir(parents=True, exist_ok=True)
        for name in structure.ENTRY_FILES:
            self.write(name)

    def test_local_links_titles_encoded_spaces_and_references(self):
        self.write("docs/My File.md")
        document = self.write("docs/index.md", (
            '[file](<My File.md> "title") [encoded](My%20File.md#section)\n'
            '[local][entry]\n[entry]: My%20File.md "title"\n'
            '[web](https://example.org/absent) [anchor](#section)\n'
        ))
        self.assertEqual(structure.check_markdown(document, self.root), [])

    def test_missing_inline_and_reference_links_report_line(self):
        document = self.write("docs/index.md", "title\n[bad](gone.md)\n[entry]: missing.md\n")
        issues = structure.check_markdown(document, self.root)
        self.assertEqual(len(issues), 2)
        self.assertIn("docs/index.md:2", issues[0])
        self.assertIn("missing.md", issues[1])

    def test_examples_do_not_become_real_links(self):
        document = self.write("docs/index.md", (
            '`[inline](absent.md)`\n```markdown\n[fenced](gone.md)\n```\n'
            '~~~text\n[tilde](gone.md)\n~~~\n    [indented](gone.md)\n'
        ))
        self.assertEqual(structure.check_markdown(document, self.root), [])

    def test_archived_references_are_not_current_errors(self):
        self.project_entries()
        self.write("docs/archive/before.md", "[historical](old-location.md)")
        self.assertEqual(structure.check_project(self.root)[0], [])

    def test_moved_resource_is_rejected_even_if_old_file_exists(self):
        self.write("scripts/sim/village_runtime.gd")
        script = self.write("tests/example.gd", 'const Runtime = preload("res://scripts/sim/village_runtime.gd")')
        issues = structure.check_script(script, self.root)
        self.assertEqual(len(issues), 1)
        self.assertIn("use res://scripts/runtime/village_runtime.gd", issues[0])

    def test_data_constants_checked_but_comments_and_dynamic_paths_ignored(self):
        self.write("data/definitions/pawns.json")
        script = self.write("scripts/example.gd", (
            'const OK_PATH = "res://data/definitions/pawns.json"\n'
            'const BAD_PATH = "res://data/definitions/absent.json"\n'
            '# const EXAMPLE = "res://does_not_exist.gd"\n'
            'var computed = "res://data/%s.json"\n'
        ))
        issues = structure.check_script(script, self.root)
        self.assertEqual(len(issues), 1)
        self.assertIn("scripts/example.gd:2", issues[0])

    def test_clean_checkout_allows_generated_runtime_outputs(self):
        self.project_entries()
        self.write("tests/runtime/helpers/replay.gd", (
            'const OUTPUT = "res://logs/replay.json"\n'
            'const SAVE = "user://saves/session.json"\n'
            'func write_result() -> void:\n'
            '    FileAccess.open(OUTPUT, FileAccess.WRITE)\n'
        ))
        self.assertFalse((self.root / "logs").exists())
        self.assertEqual(structure.check_project(self.root)[0], [])
        self.assertFalse((self.root / "logs").exists())

    def test_generated_namespace_does_not_hide_missing_source_resources(self):
        self.project_entries()
        self.write("tests/runtime/helpers/replay.gd", (
            'const OUTPUT = "res://logs/replay.json"\n'
            'const SCRIPT = preload("res://scripts/missing.gd")\n'
            'const TEXTURE = load("res://assets/missing.png")\n'
            'const LOOKALIKE = "res://logs_backup/missing.json"\n'
            'const ESCAPE = "res://logs/../scripts/missing.gd"\n'
        ))
        issues = structure.check_project(self.root)[0]
        self.assertEqual(len(issues), 4)
        self.assertTrue(any("res://scripts/missing.gd" in issue for issue in issues))
        self.assertTrue(any("res://assets/missing.png" in issue for issue in issues))
        self.assertTrue(any("res://logs_backup/missing.json" in issue for issue in issues))
        self.assertTrue(any("res://logs/../scripts/missing.gd" in issue for issue in issues))

    def test_missing_responsibility_and_task_entry_is_rejected(self):
        self.project_entries()
        (self.root / "docs/plans/foundation-priorities.md").unlink()
        (self.root / "scripts/runtime").rmdir()
        issues = structure.check_project(self.root)[0]
        self.assertTrue(any("foundation-priorities.md" in issue for issue in issues))
        self.assertTrue(any("scripts/runtime" in issue for issue in issues))

    def test_large_current_document_rejected_but_evidence_preserved(self):
        self.project_entries()
        text = "界" * (structure.MAX_ACTIVE_DOCUMENT_BYTES // 3 + 1)
        self.write("design/systems/oversized.md", text)
        evidence = self.write("docs/qa/old-measurement.md", text)
        self.write("docs/archive/original.md", text)
        issues = structure.check_project(self.root)[0]
        self.assertEqual(len(issues), 1)
        self.assertIn("design/systems/oversized.md: active document exceeds", issues[0])
        self.assertEqual(evidence.read_text(encoding="utf-8"), text)

    def test_cli_returns_nonzero_without_mutating_broken_document(self):
        self.project_entries()
        document = self.write("docs/broken.md", "[bad](absent.md)")
        before = document.read_bytes()
        result = subprocess.run(
            [sys.executable, str(TOOL_PATH), str(self.root)],
            capture_output=True, text=True, check=False,
        )
        self.assertEqual(result.returncode, 1)
        self.assertIn("missing Markdown target absent.md", result.stdout)
        self.assertEqual(document.read_bytes(), before)


if __name__ == "__main__":
    unittest.main()
