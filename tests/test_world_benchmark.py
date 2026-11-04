"""Supervisor tests use small, owned Python children, never the game/editor."""

import os
import signal
import subprocess
import sys
import time
import unittest
from pathlib import Path
from unittest import mock

TOOLS = Path(__file__).resolve().parents[1] / "tools"
sys.path.insert(0, str(TOOLS))
import world_benchmark as bench  # noqa: E402


@unittest.skipUnless(os.name == "nt" or sys.platform.startswith("linux"), "unsupported supervisor platform")
class WorldBenchmarkSupervisorTests(unittest.TestCase):
    def child(self, code: str) -> list[str]:
        return [sys.executable, "-c", code]

    def test_linux_cleanup_keeps_leader_unreaped_and_runs_only_once(self) -> None:
        # This contract can also be exercised on Windows; the live Linux
        # process-group behavior is checked separately when Linux is available.
        process = mock.Mock(pid=12345)
        job = bench._LinuxJob(bench.MAX_BYTES)
        job.attach(process)
        with (mock.patch.object(signal, "SIGKILL", 9, create=True),
              mock.patch.multiple(os, waitid=mock.DEFAULT, killpg=mock.DEFAULT,
                                  P_PID=1, WEXITED=4, WNOHANG=1, WNOWAIT=0x1000000,
                                  create=True) as patched):
            patched["waitid"].return_value = object()
            self.assertTrue(job.exited(process))
            job.close()
            job.close()
            patched["waitid"].assert_has_calls([mock.call(1, process.pid, 4 | 1 | 0x1000000)] * 2)
            self.assertEqual(patched["waitid"].call_count, 2)
            patched["killpg"].assert_called_once_with(process.pid, signal.SIGKILL)
        process.poll.assert_not_called()

    def test_linux_refuses_to_signal_a_reaped_group_leader(self) -> None:
        process = mock.Mock(pid=12345)
        job = bench._LinuxJob(bench.MAX_BYTES)
        job.attach(process)
        with (mock.patch.object(signal, "SIGKILL", 9, create=True),
              mock.patch.multiple(os, waitid=mock.DEFAULT, killpg=mock.DEFAULT,
                                  P_PID=1, WEXITED=4, WNOHANG=1, WNOWAIT=0x1000000,
                                  create=True) as patched):
            patched["waitid"].side_effect = ChildProcessError("already reaped")
            with self.assertRaisesRegex(RuntimeError, "refusing to signal"):
                job.close()
            job.close()  # A failed cleanup must never retry the numeric ID.
            patched["killpg"].assert_not_called()

    def test_success_captures_result_and_memory(self) -> None:
        command = self.child('import time; time.sleep(0.2); print(\'BENCHMARK_RESULT {"ok": true}\')')
        result = bench.run_guarded(command, 3, bench.MAX_BYTES)
        self.assertEqual(result["status"], "success", result)
        self.assertGreater(result["memory"]["samples"], 0)
        self.assertGreater(result["memory"]["peak_working_bytes"], 0)
        self.assertEqual(bench._parse_worker(result), {"ok": True})

    def test_timeout_stops_owned_child(self) -> None:
        start = time.monotonic()
        result = bench.run_guarded(self.child("import time; time.sleep(10)"), 0.2, bench.MAX_BYTES)
        self.assertEqual(result["status"], "timeout", result)
        self.assertLess(time.monotonic() - start, 4)
        self.assertIsNotNone(result["exit_code"])

    def test_exited_leader_does_not_leave_descendant_holding_output(self) -> None:
        # The direct child finishes normally while its descendant still owns
        # stdout and sleeps. The supervisor must clean up the descendant too.
        code = """import subprocess, sys, time
child = subprocess.Popen([sys.executable, '-c', 'import time; time.sleep(10)'])
print('DESCENDANT_PID', child.pid, flush=True)
time.sleep(0.3)
"""
        observations = []
        if sys.platform.startswith("linux"):
            real_killpg = os.killpg

            def checked_killpg(pgid: int, sig: int) -> None:
                # The leader must still be waitable, hence its PID cannot be
                # recycled into an unrelated process group before this signal.
                info = os.waitid(os.P_PID, pgid, os.WEXITED | os.WNOHANG | os.WNOWAIT)
                observations.append((pgid, info))
                real_killpg(pgid, sig)

            with mock.patch.object(os, "killpg", side_effect=checked_killpg):
                result = bench.run_guarded(self.child(code), 3, bench.MAX_BYTES)
        else:
            result = bench.run_guarded(self.child(code), 3, bench.MAX_BYTES)
        self.assertEqual(result["status"], "success", result)
        self.assertEqual(result["exit_code"], 0, result)
        self.assertGreater(result["memory"]["samples"], 0, result)
        descendant_pid = int(result["output"].split("DESCENDANT_PID ", 1)[1].split()[0])
        if sys.platform.startswith("linux"):
            self.assertEqual(len(observations), 1)
            self.assertIsNotNone(observations[0][1])
            self.assertEqual(observations[0][0], observations[0][1].si_pid)
            deadline = time.monotonic() + 2
            status_path = Path(f"/proc/{descendant_pid}/stat")
            while time.monotonic() < deadline:
                try:
                    state = status_path.read_text().rsplit(") ", 1)[1].split()[0]
                except FileNotFoundError:
                    break
                if state == "Z":  # A zombie has stopped and cannot retain the pipe.
                    break
                time.sleep(0.05)
            else:
                self.fail("owned descendant was still running after cleanup")
        else:
            import ctypes
            from ctypes import wintypes

            kernel = ctypes.WinDLL("kernel32", use_last_error=True)
            kernel.OpenProcess.argtypes = [wintypes.DWORD, wintypes.BOOL, wintypes.DWORD]
            kernel.OpenProcess.restype = wintypes.HANDLE
            kernel.WaitForSingleObject.argtypes = [wintypes.HANDLE, wintypes.DWORD]
            kernel.WaitForSingleObject.restype = wintypes.DWORD
            kernel.CloseHandle.argtypes = [wintypes.HANDLE]
            handle = kernel.OpenProcess(0x00100000, False, descendant_pid)  # SYNCHRONIZE
            if handle:
                try:
                    self.assertEqual(kernel.WaitForSingleObject(handle, 2000), 0,
                                     "owned descendant was still running after cleanup")
                finally:
                    kernel.CloseHandle(handle)
            else:
                self.assertEqual(ctypes.get_last_error(), 87)  # PID no longer exists.

    def test_os_memory_limit_prevents_oversized_allocation(self) -> None:
        # Exercise the actual OS quota, independently of the sampled-memory
        # cutoff. The child should survive to report an allocation failure.
        code = """import sys, time
time.sleep(0.1)
try:
    data = bytearray(256 * 1024 * 1024)
except MemoryError:
    print('allocation refused by OS budget', flush=True)
    sys.exit(7)
sys.exit(0)
"""
        result = bench.run_guarded(self.child(code), 3, 96 * 1024**2)
        self.assertEqual(result["status"], "worker_error", result)
        self.assertEqual(result["exit_code"], 7, result)
        self.assertIn("allocation refused by OS budget", result["output"])

    def test_memory_overflow_stops_only_the_guarded_child(self) -> None:
        sibling = subprocess.Popen(self.child("import time; time.sleep(10)"), stdout=subprocess.DEVNULL)
        try:
            fake_sample = lambda _process: bench._MemorySample(bench.MAX_BYTES, 0, bench.MAX_BYTES)
            result = bench.run_guarded(self.child("import time; time.sleep(10)"), 3, bench.MAX_BYTES, fake_sample)
            self.assertEqual(result["status"], "memory_limit", result)
            self.assertIsNotNone(result["exit_code"])
            self.assertIsNone(sibling.poll(), "unrelated process must remain running")
        finally:
            sibling.terminate()
            sibling.wait(timeout=5)

    def test_budget_and_worker_error_do_not_report_success(self) -> None:
        with self.assertRaises(ValueError):
            bench.run_guarded(self.child("pass"), 31, bench.MAX_BYTES)
        with self.assertRaises(ValueError):
            bench.run_guarded(self.child("pass"), 1, bench.MAX_BYTES + 1)
        result = bench.run_guarded(self.child("import time; time.sleep(0.1); raise SystemExit(3)"), 3, bench.MAX_BYTES)
        self.assertEqual(result["status"], "worker_error")
        self.assertIsNone(bench._parse_worker(result))
        self.assertIsNone(bench._parse_worker({"status": "success", "output_truncated": False,
                                               "output": "SCRIPT ERROR: bad\nBENCHMARK_RESULT {}"}))


if __name__ == "__main__":
    unittest.main()
