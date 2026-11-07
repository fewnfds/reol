"""A Godot error must fail the gate even when the process exits successfully."""

import importlib.util
import contextlib
import io
from pathlib import Path
import subprocess
import tempfile
import unittest
from unittest.mock import patch


spec = importlib.util.spec_from_file_location(
    "reol_godot_runner", Path(__file__).resolve().parents[1] / "tools" / "godot.py"
)
godot_runner = importlib.util.module_from_spec(spec)
spec.loader.exec_module(godot_runner)


class GodotExitTests(unittest.TestCase):
    def run_output(self, output: str, code: int = 0) -> int:
        with tempfile.TemporaryDirectory() as directory:
            result = subprocess.CompletedProcess(["godot"], code, stdout=output)
            with patch.object(godot_runner, "LOG_DIR", Path(directory)):
                with patch.object(godot_runner.subprocess, "run", return_value=result):
                    return godot_runner._run(["godot"], "test")

    def test_script_error_cannot_be_green(self):
        self.assertEqual(self.run_output("SCRIPT ERROR: Invalid call.\nResults: 1 passed\n"), 1)

    def test_engine_error_cannot_be_green(self):
        self.assertEqual(self.run_output("  ERROR: Failed to load script.\n"), 1)

    def test_clean_output_and_original_failure(self):
        self.assertEqual(self.run_output("Results: 3 passed, 0 failed\n"), 0)
        self.assertEqual(self.run_output("Results: 2 passed, 1 failed\n", 5), 5)

    def test_timeout_preserves_partial_text_and_bytes(self):
        for partial in ["RUN unfinished\n", b"RUN unfinished\n\xe4\xb8\xad"]:
            with self.subTest(partial=partial):
                with tempfile.TemporaryDirectory() as directory:
                    location = Path(directory)
                    timeout = subprocess.TimeoutExpired(["godot"], 1, output=partial)
                    with patch.object(godot_runner, "LOG_DIR", location):
                        with patch.object(godot_runner.subprocess, "run", side_effect=timeout):
                            self.assertEqual(godot_runner._run(["godot"], "test", timeout=1), 124)
                    logs = list(location.glob("test-*.log"))
                    self.assertEqual(len(logs), 1)
                    text = logs[0].read_text(encoding="utf-8")
                    self.assertIn("RUN unfinished", text)
                    self.assertIn("ERROR: timed out after 1s", text)
                    if isinstance(partial, bytes):
                        self.assertIn("中", text)


class GodotTestTimeoutTests(unittest.TestCase):
    def test_default_timeout_remains_900_seconds(self):
        for command in ("test", "check"):
            with self.subTest(command=command):
                args = godot_runner.build_parser().parse_args([command])
                self.assertEqual(args.test_timeout, 900)

    def test_explicit_positive_timeout(self):
        for command in ("test", "check"):
            for seconds in (1, 1800):
                with self.subTest(command=command, seconds=seconds):
                    args = godot_runner.build_parser().parse_args(
                        [command, "--test-timeout", str(seconds)]
                    )
                    self.assertEqual(args.test_timeout, seconds)

    def test_invalid_timeout_rejected_before_running(self):
        for command in ("test", "check"):
            for value in ("0", "-1", "1.5", "seconds"):
                with self.subTest(command=command, value=value):
                    with contextlib.redirect_stderr(io.StringIO()):
                        with self.assertRaises(SystemExit) as raised:
                            godot_runner.build_parser().parse_args(
                                [command, "--test-timeout", value]
                            )
                    self.assertEqual(raised.exception.code, 2)

    def test_timeout_reaches_test_stage_only(self):
        for command in ("test", "check"):
            for timeout in (900, 1800):
                with self.subTest(command=command, timeout=timeout):
                    arguments = [command]
                    if timeout != 900:
                        arguments += ["--test-timeout", str(timeout)]
                    args = godot_runner.build_parser().parse_args(arguments)
                    with patch.object(godot_runner, "_require_godot", return_value=Path("godot")):
                        with patch.object(godot_runner, "_run", return_value=0) as run:
                            with contextlib.redirect_stdout(io.StringIO()):
                                self.assertEqual(args.func(args), 0)
                    names = [call.args[1] for call in run.call_args_list]
                    limits = [call.kwargs["timeout"] for call in run.call_args_list]
                    self.assertEqual(names, ["test"] if command == "test" else ["check-structure", "check-import", "check-test"])
                    self.assertEqual(limits, [timeout] if command == "test" else [60, 600, timeout])
                    command_line = run.call_args.args[0]
                    self.assertEqual(command_line[command_line.index("--script") + 1], "res://tests/run_tests.gd")
                    self.assertIn("--timing-report", command_line[command_line.index("--") + 1:])

    def test_custom_timeout_still_fails_test_and_check(self):
        for command in ("test", "check"):
            with self.subTest(command=command):
                args = godot_runner.build_parser().parse_args(
                    [command, "--test-timeout", "1800"]
                )
                results = [124] if command == "test" else [0, 0, 124]
                with patch.object(godot_runner, "_require_godot", return_value=Path("godot")):
                    with patch.object(godot_runner, "_run", side_effect=results):
                        with contextlib.redirect_stderr(io.StringIO()):
                            self.assertEqual(args.func(args), 124 if command == "test" else 1)


class GodotSuiteSelectionTests(unittest.TestCase):
    def test_exact_suites_and_report_are_forwarded_as_user_arguments(self):
        with tempfile.TemporaryDirectory() as directory:
            report = Path(directory) / "timings" / "selected.jsonl"
            args = godot_runner.build_parser().parse_args([
                "test", "--suite", "test_world_map_data", "--suite", "test_terrain_edits",
                "--timing-report", str(report),
            ])
            command = godot_runner._test_command(Path("godot"), args, "test")
            self.assertEqual(command[command.index("--") + 1:], [
                "--suite", "test_world_map_data", "--suite", "test_terrain_edits",
                "--timing-report", str(report.resolve()),
            ])
            self.assertTrue(report.parent.is_dir())

    def test_listing_does_not_create_a_timing_report(self):
        args = godot_runner.build_parser().parse_args(["test", "--list-suites"])
        with tempfile.TemporaryDirectory() as directory:
            with patch.object(godot_runner, "LOG_DIR", Path(directory) / "unused"):
                command = godot_runner._test_command(Path("godot"), args, "test")
            self.assertEqual(command[command.index("--") + 1:], ["--list-suites"])
            self.assertEqual(list(Path(directory).iterdir()), [])

    def test_default_report_is_unique_and_partial_selection_is_not_a_full_check(self):
        args = godot_runner.build_parser().parse_args(["check"])
        with tempfile.TemporaryDirectory() as directory:
            with patch.object(godot_runner, "LOG_DIR", Path(directory)):
                first = godot_runner._test_command(Path("godot"), args, "check-test")
                second = godot_runner._test_command(Path("godot"), args, "check-test")
            self.assertNotEqual(first[-1], second[-1])
            self.assertEqual(Path(first[-1]).parent, Path(directory).resolve())
        with contextlib.redirect_stderr(io.StringIO()):
            with self.assertRaises(SystemExit) as raised:
                godot_runner.build_parser().parse_args(["check", "--suite", "test_world_map_data"])
        self.assertEqual(raised.exception.code, 2)


if __name__ == "__main__":
    unittest.main()
