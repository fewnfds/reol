"""Check that local Codex setup never overwrites unrelated user settings."""

from __future__ import annotations

import contextlib
import importlib.util
import io
import tempfile
import tomllib
import unittest
from pathlib import Path
from unittest.mock import patch

SPEC = importlib.util.spec_from_file_location(
    "setup_codex", Path(__file__).resolve().parents[1] / "tools" / "setup_codex.py"
)
SETUP = importlib.util.module_from_spec(SPEC)
SPEC.loader.exec_module(SETUP)


class CodexSetupTests(unittest.TestCase):
    def setUp(self) -> None:
        self.workspace = tempfile.TemporaryDirectory(prefix="reol-codex-test-")
        self.addCleanup(self.workspace.cleanup)
        self.root = Path(self.workspace.name)
        self.config = self.root / ".codex" / "config.toml"
        skill = self.root / ".agents" / "skills" / "reol-project"
        skill.mkdir(parents=True)
        (skill / "SKILL.md").write_text("test fixture", encoding="utf-8")

    def run_setup(self, *arguments: str) -> int:
        with (
            patch.object(SETUP, "ROOT", self.root),
            patch.object(SETUP, "CONFIG", self.config),
            patch("sys.argv", ["setup_codex.py", *arguments]),
            contextlib.redirect_stdout(io.StringIO()),
            contextlib.redirect_stderr(io.StringIO()),
        ):
            return SETUP.main()

    def test_adds_servers_without_changing_existing_settings(self) -> None:
        original = '# Keep this comment\nmodel = "personal-choice"\n\n[mcp_servers.existing]\nurl = "https://example.com/mcp"\n'
        self.config.parent.mkdir()
        self.config.write_text(original, encoding="utf-8")

        self.assertEqual(self.run_setup(), 0)
        updated = self.config.read_text(encoding="utf-8")
        self.assertTrue(updated.startswith(original.rstrip()))
        data = tomllib.loads(updated)
        self.assertEqual(data["model"], "personal-choice")
        self.assertEqual(data["mcp_servers"]["existing"]["url"], "https://example.com/mcp")
        self.assertIn("godot", data["mcp_servers"])
        self.assertIn("context7", data["mcp_servers"])
        backup = next(self.config.parent.glob("*.bak"))
        self.assertEqual(backup.read_text(encoding="utf-8"), original)

    def test_second_run_is_no_op(self) -> None:
        self.assertEqual(self.run_setup(), 0)
        first = self.config.read_bytes()
        self.assertEqual(self.run_setup(), 0)
        self.assertEqual(self.run_setup("--check"), 0)
        self.assertEqual(self.config.read_bytes(), first)
        self.assertFalse(list(self.config.parent.glob("*.bak")))

    def test_conflicting_server_is_preserved(self) -> None:
        self.config.parent.mkdir()
        self.config.write_text('[mcp_servers.godot]\ncommand = "custom-server"\n', encoding="utf-8")
        original = self.config.read_bytes()
        self.assertEqual(self.run_setup(), 1)
        self.assertEqual(self.config.read_bytes(), original)
        self.assertFalse(list(self.config.parent.glob("*.bak")))

    def test_check_mode_does_not_write_missing_config(self) -> None:
        self.assertEqual(self.run_setup("--check"), 1)
        self.assertFalse(self.config.exists())


if __name__ == "__main__":
    unittest.main()
