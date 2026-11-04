"""Check that local Codex setup never overwrites unrelated user settings."""

from __future__ import annotations

import contextlib
import importlib.util
import io
import os
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
        stdout = io.StringIO()
        stderr = io.StringIO()
        with (
            patch.object(SETUP, "ROOT", self.root),
            patch.object(SETUP, "CONFIG", self.config),
            patch("sys.argv", ["setup_codex.py", *arguments]),
            contextlib.redirect_stdout(stdout),
            contextlib.redirect_stderr(stderr),
        ):
            result = SETUP.main()
        self.stdout = stdout.getvalue()
        self.stderr = stderr.getvalue()
        return result

    def test_adds_servers_without_changing_existing_settings(self) -> None:
        original = (
            '# Keep this comment\r\nmodel = "personal-choice"\r\n'
            'approval_policy = "on-request"\r\nsandbox_mode = "workspace-write"\r\n\r\n'
            '[mcp_servers.existing]\r\nurl = "https://example.com/mcp"\r\n'
        )
        self.config.parent.mkdir()
        self.config.write_bytes(original.encode("utf-8"))

        self.assertEqual(self.run_setup(), 0)
        updated = self.config.read_bytes().decode("utf-8")
        self.assertTrue(updated.startswith(original))
        self.assertNotIn("\n", updated.replace("\r\n", ""))
        data = tomllib.loads(updated)
        self.assertEqual(data["model"], "personal-choice")
        self.assertEqual(data["approval_policy"], "on-request")
        self.assertEqual(data["sandbox_mode"], "workspace-write")
        self.assertEqual(data["mcp_servers"]["existing"]["url"], "https://example.com/mcp")
        self.assertFalse(data["mcp_servers"]["godot"]["enabled"])
        self.assertTrue(data["mcp_servers"]["context7"]["enabled"])
        self.assertNotIn("langchain-docs", data["mcp_servers"])
        self.assertIn("langchain-docs: inherited server is not managed", self.stdout)
        backup = next(self.config.parent.glob("*.bak"))
        self.assertEqual(backup.read_bytes(), original.encode("utf-8"))

    def test_second_run_is_no_op(self) -> None:
        self.assertEqual(self.run_setup(), 0)
        first = self.config.read_bytes()
        self.assertEqual(self.run_setup(), 0)
        self.assertEqual(self.run_setup("--check"), 0)
        self.assertEqual(self.config.read_bytes(), first)
        self.assertFalse(list(self.config.parent.glob("*.bak")))

    def test_existing_temporary_file_is_not_overwritten(self) -> None:
        self.config.parent.mkdir()
        existing_temp = self.config.with_suffix(".toml.tmp")
        existing_temp.write_text("owned by someone else", encoding="utf-8")
        self.assertEqual(self.run_setup(), 0)
        self.assertEqual(existing_temp.read_text(encoding="utf-8"), "owned by someone else")

    def test_conflicting_server_is_preserved_while_missing_server_is_added(self) -> None:
        self.config.parent.mkdir()
        self.config.write_text('[mcp_servers.godot]\ncommand = "custom-server"\n', encoding="utf-8")
        original = self.config.read_bytes()
        self.assertEqual(self.run_setup(), 0)
        self.assertTrue(self.config.read_bytes().startswith(original))
        self.assertEqual(tomllib.loads(self.config.read_text(encoding="utf-8"))["mcp_servers"]["godot"]["command"], "custom-server")
        self.assertIn("custom connection", self.stdout)
        self.assertEqual(self.run_setup("--check"), 0)

    def test_existing_enabled_choices_are_preserved(self) -> None:
        self.assertEqual(self.run_setup(), 0)
        text = self.config.read_text(encoding="utf-8")
        text = text.replace("enabled = false", "enabled = true", 1)
        context_start = text.index("[mcp_servers.context7]")
        text = text[:context_start] + text[context_start:].replace("enabled = true", "enabled = false", 1)
        self.config.write_text(text, encoding="utf-8")
        original = self.config.read_bytes()
        self.assertEqual(self.run_setup(), 0)
        self.assertIn("godot (enabled; preserved)", self.stdout)
        self.assertIn("context7 (disabled; preserved)", self.stdout)
        self.assertEqual(self.run_setup("--check"), 0)
        self.assertEqual(self.config.read_bytes(), original)

    def test_enable_backup_from_missing_and_check(self) -> None:
        self.assertEqual(self.run_setup("--check", "--enable-backup-godot"), 1)
        self.assertIn("--enable-backup-godot", self.stdout)
        self.assertFalse(self.config.exists())
        self.assertEqual(self.run_setup("--enable-backup-godot"), 0)
        data = tomllib.loads(self.config.read_text(encoding="utf-8"))
        self.assertTrue(data["mcp_servers"]["godot"]["enabled"])
        self.assertEqual(self.run_setup("--check", "--enable-backup-godot"), 0)
        self.assertEqual(self.run_setup("--check"), 0)

    def test_enable_generated_backup_changes_only_its_flag(self) -> None:
        self.assertEqual(self.run_setup(), 0)
        text = self.config.read_text(encoding="utf-8")
        text = text.replace("startup_timeout_sec = 65", "startup_timeout_sec = 99", 1)
        text = text.replace("enabled = false", "enabled = false # user comment", 1)
        text = text.replace("[mcp_servers.context7]", '[mcp_servers.godot.env]\nCUSTOM = "kept"\n\n[mcp_servers.context7]')
        original = text.replace("\n", "\r\n").encode("utf-8")
        self.config.write_bytes(original)
        self.assertEqual(self.run_setup("--check", "--enable-backup-godot"), 1)
        self.assertEqual(self.config.read_bytes(), original)
        self.assertFalse(list(self.config.parent.glob("*.bak")))
        self.assertEqual(self.run_setup("--enable-backup-godot"), 0)
        expected = original.replace(b"enabled = false # user comment", b"enabled = true # user comment", 1)
        self.assertEqual(self.config.read_bytes(), expected)
        self.assertEqual(next(self.config.parent.glob("*.bak")).read_bytes(), original)
        self.assertEqual(self.run_setup("--check", "--enable-backup-godot"), 0)
        self.assertEqual(self.run_setup(), 0)
        self.assertEqual(self.config.read_bytes(), expected)

    def test_enable_custom_or_unrecognizable_backup_refuses_to_edit(self) -> None:
        for unrecognizable in (False, True):
            with self.subTest(unrecognizable=unrecognizable):
                self.assertEqual(self.run_setup(), 0)
                text = self.config.read_text(encoding="utf-8")
                if unrecognizable:
                    text = text.replace("enabled = false", '"enabled" = false', 1)
                else:
                    text = text.replace("command = ", 'command = "custom-server" # ', 1)
                self.config.write_text(text, encoding="utf-8")
                original = self.config.read_bytes()
                self.assertEqual(self.run_setup("--enable-backup-godot"), 1)
                self.assertIn("manually", self.stderr)
                self.assertEqual(self.config.read_bytes(), original)
                self.config.unlink()

    def test_existing_langchain_entry_and_global_file_are_untouched(self) -> None:
        codex_home = self.root / "global-home"
        codex_home.mkdir()
        global_config = codex_home / "config.toml"
        global_original = '[mcp_servers.langchain-docs]\ncommand = "custom-server"\n'
        global_config.write_text(global_original, encoding="utf-8")
        self.config.parent.mkdir()
        project_original = '[mcp_servers.langchain-docs]\ncommand = "local-custom"\nenabled = true\n'
        self.config.write_text(project_original, encoding="utf-8")
        with patch.dict(os.environ, {"CODEX_HOME": str(codex_home)}):
            self.assertEqual(self.run_setup(), 0)
        self.assertTrue(self.config.read_text(encoding="utf-8").startswith(project_original))
        self.assertEqual(global_config.read_text(encoding="utf-8"), global_original)
        self.assertEqual(tomllib.loads(self.config.read_text(encoding="utf-8"))["mcp_servers"]["langchain-docs"]["command"], "local-custom")

    def test_inherited_langchain_is_not_guessed_or_overwritten(self) -> None:
        codex_home = self.root / "global-home"
        codex_home.mkdir()
        global_config = codex_home / "config.toml"
        original = '[mcp_servers.langchain-docs]\ncommand = "custom-server"\n'
        global_config.write_text(original, encoding="utf-8")
        with patch.dict(os.environ, {"CODEX_HOME": str(codex_home)}):
            self.assertEqual(self.run_setup(), 0)
        self.assertNotIn("langchain-docs", tomllib.loads(self.config.read_text(encoding="utf-8"))["mcp_servers"])
        self.assertEqual(global_config.read_text(encoding="utf-8"), original)
        self.assertIn("inherited server is not managed", self.stdout)

    def test_malformed_existing_server_is_preserved(self) -> None:
        self.config.parent.mkdir()
        self.config.write_text('mcp_servers = "not-a-table"\n', encoding="utf-8")
        original = self.config.read_bytes()
        self.assertEqual(self.run_setup(), 1)
        self.assertIn("not a table", self.stderr)
        self.assertEqual(self.config.read_bytes(), original)
        self.assertFalse(list(self.config.parent.glob("*.bak")))

    def test_inline_mcp_table_cannot_be_safely_extended(self) -> None:
        self.config.parent.mkdir()
        self.config.write_text('mcp_servers = { existing = { url = "https://example.com" } }\n', encoding="utf-8")
        original = self.config.read_bytes()
        for arguments in ((), ("--check",)):
            with self.subTest(arguments=arguments):
                self.assertEqual(self.run_setup(*arguments), 1)
                self.assertIn("Cannot safely append", self.stderr)
                self.assertEqual(self.config.read_bytes(), original)
                self.assertFalse(list(self.config.parent.glob("*.bak")))

    def test_help_explains_backup_and_check(self) -> None:
        output = io.StringIO()
        with patch("sys.argv", ["setup_codex.py", "--help"]), contextlib.redirect_stdout(output):
            with self.assertRaises(SystemExit) as raised:
                SETUP.main()
        self.assertEqual(raised.exception.code, 0)
        self.assertIn("--enable-backup-godot", output.getvalue())
        self.assertIn("with --check, only verify it is enabled", " ".join(output.getvalue().split()))
        self.assertIn("Inherited langchain-docs", output.getvalue())
        self.assertIn("codex mcp list", output.getvalue())

    def test_check_mode_does_not_write_missing_config(self) -> None:
        self.assertEqual(self.run_setup("--check"), 1)
        self.assertFalse(self.config.exists())


if __name__ == "__main__":
    unittest.main()
