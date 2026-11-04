#!/usr/bin/env python3
"""Run a small real-world headless benchmark under an owned process budget.

This measures the existing opening, not a large generated world or rendered FPS.
Each run gets its own child process and JSON report. No existing process is touched.
Windows uses a job-object commit limit and sampled working/private bytes; Linux
uses a per-process RLIMIT_AS and sampled /proc metrics. Linux cleanup covers the
owned process group, not descendants that deliberately leave that group. Other
platforms fail closed.
"""

from __future__ import annotations

import argparse
import ctypes
import json
import os
import platform
import signal
import subprocess
import sys
import threading
import time
from datetime import datetime, timezone
from pathlib import Path
from typing import Callable

import godot

ROOT = Path(__file__).resolve().parents[1]
MAX_SECONDS = 30.0
MAX_BYTES = 1024**3
MAX_OUTPUT = 512 * 1024
POLL_SECONDS = 0.05
MAX_CELLS = 512 * 512
WORKER = "res://tests/benchmarks/world_baseline.gd"


class _MemorySample:
    def __init__(self, working: int, private: int, peak_working: int) -> None:
        self.working = working
        self.private = private
        self.peak_working = peak_working


class _WindowsJob:
    """A kernel-enforced commit budget and lifetime for exactly our child tree."""

    def __init__(self, limit: int) -> None:
        from ctypes import wintypes

        class BasicLimit(ctypes.Structure):
            _fields_ = [
                ("process_time", ctypes.c_longlong), ("job_time", ctypes.c_longlong),
                ("flags", wintypes.DWORD), ("min_working", ctypes.c_size_t),
                ("max_working", ctypes.c_size_t), ("active_limit", wintypes.DWORD),
                ("affinity", ctypes.c_size_t), ("priority", wintypes.DWORD),
                ("scheduling", wintypes.DWORD),
            ]

        class IoCounters(ctypes.Structure):
            _fields_ = [(name, ctypes.c_ulonglong) for name in (
                "reads", "writes", "other", "read_bytes", "write_bytes", "other_bytes",
            )]

        class ExtendedLimit(ctypes.Structure):
            _fields_ = [
                ("basic", BasicLimit), ("io", IoCounters),
                ("process_memory", ctypes.c_size_t), ("job_memory", ctypes.c_size_t),
                ("peak_process", ctypes.c_size_t), ("peak_job", ctypes.c_size_t),
            ]

        class MemoryCounters(ctypes.Structure):
            _fields_ = [
                ("cb", wintypes.DWORD), ("page_fault_count", wintypes.DWORD),
                ("peak_working", ctypes.c_size_t), ("working", ctypes.c_size_t),
                ("quota_peak_paged", ctypes.c_size_t), ("quota_paged", ctypes.c_size_t),
                ("quota_peak_nonpaged", ctypes.c_size_t), ("quota_nonpaged", ctypes.c_size_t),
                ("pagefile", ctypes.c_size_t), ("peak_pagefile", ctypes.c_size_t),
                ("private", ctypes.c_size_t),
            ]

        class ThreadEntry(ctypes.Structure):
            _fields_ = [
                ("size", wintypes.DWORD), ("usage", wintypes.DWORD),
                ("thread_id", wintypes.DWORD), ("owner_id", wintypes.DWORD),
                ("base_priority", wintypes.LONG), ("delta_priority", wintypes.LONG),
                ("flags", wintypes.DWORD),
            ]

        self._memory_type = MemoryCounters
        self._thread_type = ThreadEntry
        self._kernel = ctypes.WinDLL("kernel32", use_last_error=True)
        self._psapi = ctypes.WinDLL("psapi", use_last_error=True)
        self._kernel.CreateJobObjectW.argtypes = [ctypes.c_void_p, wintypes.LPCWSTR]
        self._kernel.CreateJobObjectW.restype = wintypes.HANDLE
        self._kernel.SetInformationJobObject.argtypes = [wintypes.HANDLE, ctypes.c_int, ctypes.c_void_p, wintypes.DWORD]
        self._kernel.SetInformationJobObject.restype = wintypes.BOOL
        self._kernel.AssignProcessToJobObject.argtypes = [wintypes.HANDLE, wintypes.HANDLE]
        self._kernel.AssignProcessToJobObject.restype = wintypes.BOOL
        self._kernel.TerminateJobObject.argtypes = [wintypes.HANDLE, wintypes.UINT]
        self._kernel.TerminateJobObject.restype = wintypes.BOOL
        self._kernel.CloseHandle.argtypes = [wintypes.HANDLE]
        self._kernel.CreateToolhelp32Snapshot.argtypes = [wintypes.DWORD, wintypes.DWORD]
        self._kernel.CreateToolhelp32Snapshot.restype = wintypes.HANDLE
        self._kernel.Thread32First.argtypes = [wintypes.HANDLE, ctypes.POINTER(ThreadEntry)]
        self._kernel.Thread32First.restype = wintypes.BOOL
        self._kernel.Thread32Next.argtypes = [wintypes.HANDLE, ctypes.POINTER(ThreadEntry)]
        self._kernel.Thread32Next.restype = wintypes.BOOL
        self._kernel.OpenThread.argtypes = [wintypes.DWORD, wintypes.BOOL, wintypes.DWORD]
        self._kernel.OpenThread.restype = wintypes.HANDLE
        self._kernel.ResumeThread.argtypes = [wintypes.HANDLE]
        self._kernel.ResumeThread.restype = wintypes.DWORD
        self._psapi.GetProcessMemoryInfo.argtypes = [wintypes.HANDLE, ctypes.c_void_p, wintypes.DWORD]
        self._psapi.GetProcessMemoryInfo.restype = wintypes.BOOL
        self._job = self._kernel.CreateJobObjectW(None, None)
        if not self._job:
            raise OSError(ctypes.get_last_error(), "CreateJobObjectW failed")
        settings = ExtendedLimit()
        # KILL_ON_JOB_CLOSE | PROCESS_MEMORY | JOB_MEMORY.
        settings.basic.flags = 0x2000 | 0x100 | 0x200
        settings.process_memory = limit
        settings.job_memory = limit
        if not self._kernel.SetInformationJobObject(self._job, 9, ctypes.byref(settings), ctypes.sizeof(settings)):
            error = ctypes.get_last_error()
            self.close()
            raise OSError(error, "SetInformationJobObject failed")

    def attach(self, process: subprocess.Popen[bytes]) -> None:
        if not self._kernel.AssignProcessToJobObject(self._job, int(process._handle)):
            raise OSError(ctypes.get_last_error(), "AssignProcessToJobObject failed")

    def resume(self, process: subprocess.Popen[bytes]) -> None:
        # The child was created suspended, so its original thread is the only
        # thread it can have created. Apply the job budget before resuming it.
        snapshot = self._kernel.CreateToolhelp32Snapshot(0x4, 0)  # TH32CS_SNAPTHREAD
        if snapshot == ctypes.c_void_p(-1).value:
            raise OSError(ctypes.get_last_error(), "thread snapshot failed")
        try:
            entry = self._thread_type()
            entry.size = ctypes.sizeof(entry)
            found = self._kernel.Thread32First(snapshot, ctypes.byref(entry))
            while found:
                if entry.owner_id == process.pid:
                    thread = self._kernel.OpenThread(0x2, False, entry.thread_id)  # THREAD_SUSPEND_RESUME
                    if not thread:
                        raise OSError(ctypes.get_last_error(), "open owned child thread failed")
                    try:
                        count = self._kernel.ResumeThread(thread)
                        if count == 0xFFFFFFFF:
                            raise OSError(ctypes.get_last_error(), "resume owned child thread failed")
                        if count != 1:
                            raise OSError("owned child did not have exactly one suspension")
                    finally:
                        self._kernel.CloseHandle(thread)
                    return
                found = self._kernel.Thread32Next(snapshot, ctypes.byref(entry))
            raise OSError("suspended child thread not found")
        finally:
            self._kernel.CloseHandle(snapshot)

    def sample(self, process: subprocess.Popen[bytes]) -> _MemorySample:
        data = self._memory_type()
        data.cb = ctypes.sizeof(data)
        if not self._psapi.GetProcessMemoryInfo(int(process._handle), ctypes.byref(data), data.cb):
            raise OSError(ctypes.get_last_error(), "GetProcessMemoryInfo failed")
        return _MemorySample(data.working, data.private, data.peak_working)

    def exited(self, process: subprocess.Popen[bytes]) -> bool:
        return process.poll() is not None

    def terminate(self, _process: subprocess.Popen[bytes]) -> None:
        if self._job and not self._kernel.TerminateJobObject(self._job, 1):
            raise OSError(ctypes.get_last_error(), "TerminateJobObject failed")

    def close(self) -> None:
        if self._job:
            self._kernel.CloseHandle(self._job)
            self._job = None


class _LinuxJob:
    """Own a process group; the address-space limit applies to each process."""

    def __init__(self, limit: int) -> None:
        self.limit = limit
        self.process: subprocess.Popen[bytes] | None = None

    def child_setup(self) -> None:
        import resource
        resource.setrlimit(resource.RLIMIT_AS, (self.limit, self.limit))

    def attach(self, process: subprocess.Popen[bytes]) -> None:
        self.process = process

    def exited(self, process: subprocess.Popen[bytes]) -> bool:
        # Do not poll or wait yet: keeping the leader's PID reserved prevents
        # its process-group ID being recycled before we clean up descendants.
        return os.waitid(os.P_PID, process.pid, os.WEXITED | os.WNOHANG | os.WNOWAIT) is not None

    def sample(self, process: subprocess.Popen[bytes]) -> _MemorySample:
        values: dict[str, int] = {}
        for line in Path(f"/proc/{process.pid}/status").read_text().splitlines():
            key, separator, value = line.partition(":")
            if separator and key in ("VmRSS", "VmHWM", "VmData"):
                values[key] = int(value.split()[0]) * 1024
        if not all(key in values for key in ("VmRSS", "VmHWM", "VmData")):
            raise OSError("required /proc memory counters unavailable")
        # VmData is writable data, not identical to Windows private commit.
        return _MemorySample(values["VmRSS"], values["VmData"], values["VmHWM"])

    def terminate(self, process: subprocess.Popen[bytes]) -> None:
        if self.process is not process:
            raise RuntimeError("cannot terminate an unowned process group")
        try:
            self.exited(process)
        except ChildProcessError as exc:
            # If another caller reaped the leader, the numeric group ID might
            # already belong to somebody else. Never signal it in that case.
            raise RuntimeError("group leader already reaped; refusing to signal its group") from exc
        try:
            os.killpg(process.pid, signal.SIGKILL)
        except ProcessLookupError:
            pass  # The owned group is already empty.

    def close(self) -> None:
        if self.process:
            try:
                self.terminate(self.process)
            finally:
                # Never signal this numeric ID again after the leader is reaped.
                self.process = None


def _new_job(limit: int) -> _WindowsJob | _LinuxJob:
    if os.name == "nt":
        return _WindowsJob(limit)
    if (sys.platform.startswith("linux") and Path("/proc/self/status").exists()
            and all(hasattr(os, name) for name in ("waitid", "P_PID", "WEXITED", "WNOHANG", "WNOWAIT"))):
        if signal.getsignal(signal.SIGCHLD) != signal.SIG_DFL:
            raise RuntimeError("safe process supervision requires the default SIGCHLD handler")
        return _LinuxJob(limit)
    raise RuntimeError("safe process memory supervision is not supported on this platform")


def _collect_output(pipe: object, buffer: bytearray, truncated: list[bool]) -> None:
    while True:
        chunk = pipe.read(8192)  # type: ignore[attr-defined]
        if not chunk:
            return
        remaining = MAX_OUTPUT - len(buffer)
        buffer.extend(chunk[:max(0, remaining)])
        if len(chunk) > remaining:
            truncated[0] = True


def run_guarded(
    command: list[str], timeout: float, memory_limit: int,
    sampler: Callable[[subprocess.Popen[bytes]], _MemorySample] | None = None,
) -> dict:
    """Run one owned process under both limits; sampler is injectable for tests."""
    if not 0 < timeout <= MAX_SECONDS or not 0 < memory_limit <= MAX_BYTES:
        raise ValueError("sample budgets exceed allowed maximums")
    job = _new_job(memory_limit)
    process: subprocess.Popen[bytes] | None = None
    output = bytearray()
    truncated = [False]
    peak_working = peak_private = samples = 0
    outcome = "start_error"
    error = ""
    start = time.monotonic()
    reader: threading.Thread | None = None
    try:
        kwargs: dict = {"cwd": ROOT, "stdout": subprocess.PIPE, "stderr": subprocess.STDOUT}
        if os.name == "nt":
            kwargs["creationflags"] = subprocess.CREATE_NO_WINDOW | 0x4  # CREATE_SUSPENDED
        else:
            kwargs["start_new_session"] = True
            kwargs["preexec_fn"] = job.child_setup
        process = subprocess.Popen(command, **kwargs)
        try:
            job.attach(process)
            if os.name == "nt":
                job.resume(process)
        except OSError:
            process.kill()
            raise
        reader = threading.Thread(target=_collect_output, args=(process.stdout, output, truncated), daemon=True)
        reader.start()
        read_memory = sampler or job.sample
        while not job.exited(process):
            if time.monotonic() - start >= timeout:
                outcome = "timeout"
                job.terminate(process)
                break
            try:
                sample = read_memory(process)
            except (OSError, ValueError) as exc:
                if job.exited(process):
                    break
                outcome, error = "monitor_error", str(exc)
                job.terminate(process)
                break
            samples += 1
            peak_working = max(peak_working, sample.working, sample.peak_working)
            peak_private = max(peak_private, sample.private)
            if sample.working >= memory_limit or sample.private >= memory_limit:
                outcome = "memory_limit"
                job.terminate(process)
                break
            time.sleep(POLL_SECONDS)
    except (OSError, subprocess.SubprocessError, RuntimeError) as exc:
        error = str(exc)
        outcome = "supervisor_error"
    finally:
        # Close before reaping: Linux must reserve the group leader's PID until
        # the whole inherited process group has been signalled. Windows closes
        # the job, which also kills descendants left by our own child.
        try:
            job.close()
        except (OSError, RuntimeError) as exc:
            outcome, error = "supervisor_error", f"process cleanup failed: {exc}"
            if os.name == "nt" and process and process.returncode is None:
                # Windows retains an identity-safe process handle. On Linux,
                # never fall back to signalling a possibly recycled PID.
                try:
                    process.kill()
                except OSError as kill_exc:
                    error += f"; child termination failed: {kill_exc}"
        if process and process.returncode is None:
            try:
                process.wait(timeout=5)
            except subprocess.SubprocessError as exc:
                outcome, error = "supervisor_error", f"child did not exit after cleanup: {exc}"
        if reader:
            reader.join(timeout=2)
            if reader.is_alive():
                outcome, error = "supervisor_error", "child output remained open after process cleanup"
        if process and process.stdout and (reader is None or not reader.is_alive()):
            process.stdout.close()
    if outcome == "start_error":
        outcome = "success" if process and process.returncode == 0 else "worker_error"
    if outcome == "success" and samples == 0:
        outcome, error = "monitor_error", "child exited before any memory sample"
    elapsed = time.monotonic() - start
    return {
        "status": outcome, "error": error, "elapsed_seconds": elapsed,
        "exit_code": process.returncode if process else None,
        "limits": {"seconds": timeout, "memory_bytes": memory_limit},
        "memory": {"peak_working_bytes": peak_working, "peak_private_sampled_bytes": peak_private,
                   "samples": samples, "interval_seconds": POLL_SECONDS,
                   "private_counter": "PrivateUsage" if os.name == "nt" else "VmData (not private commit)"},
        "output": output.decode("utf-8", errors="replace"), "output_truncated": truncated[0],
    }


def _parse_worker(result: dict) -> dict | None:
    if result["status"] != "success" or result["output_truncated"]:
        return None
    lines = result["output"].splitlines()
    if any(line.lstrip().startswith(("SCRIPT ERROR:", "ERROR:", "BENCHMARK_ERROR")) for line in lines):
        return None
    payloads = [line.removeprefix("BENCHMARK_RESULT ") for line in lines if line.startswith("BENCHMARK_RESULT ")]
    if len(payloads) != 1:
        return None
    try:
        payload = json.loads(payloads[0])
    except json.JSONDecodeError:
        return None
    return payload if isinstance(payload, dict) else None


def _bounded_int(text: str, maximum: int) -> int:
    try:
        value = int(text)
    except ValueError as exc:
        raise argparse.ArgumentTypeError("must be an integer") from exc
    if not 1 <= value <= maximum:
        raise argparse.ArgumentTypeError(f"must be between 1 and {maximum}")
    return value


def _host_metadata() -> dict:
    """Best-effort hardware details; missing values remain explicitly unknown."""
    cpu = platform.processor() or "unknown"
    memory: int | None = None
    if os.name == "nt":
        from ctypes import wintypes
        import winreg

        class MemoryStatus(ctypes.Structure):
            _fields_ = [
                ("size", wintypes.DWORD), ("load", wintypes.DWORD),
                ("total_phys", ctypes.c_ulonglong), ("avail_phys", ctypes.c_ulonglong),
                ("total_page", ctypes.c_ulonglong), ("avail_page", ctypes.c_ulonglong),
                ("total_virtual", ctypes.c_ulonglong), ("avail_virtual", ctypes.c_ulonglong),
                ("avail_extended", ctypes.c_ulonglong),
            ]

        try:
            with winreg.OpenKey(winreg.HKEY_LOCAL_MACHINE, r"HARDWARE\DESCRIPTION\System\CentralProcessor\0") as key:
                cpu = str(winreg.QueryValueEx(key, "ProcessorNameString")[0]).strip() or cpu
        except OSError:
            pass
        state = MemoryStatus()
        state.size = ctypes.sizeof(state)
        kernel = ctypes.WinDLL("kernel32", use_last_error=True)
        kernel.GlobalMemoryStatusEx.argtypes = [ctypes.POINTER(MemoryStatus)]
        kernel.GlobalMemoryStatusEx.restype = wintypes.BOOL
        if kernel.GlobalMemoryStatusEx(ctypes.byref(state)):
            memory = int(state.total_phys)
    elif sys.platform.startswith("linux"):
        try:
            for line in Path("/proc/cpuinfo").read_text().splitlines():
                if line.startswith("model name"):
                    cpu = line.partition(":")[2].strip() or cpu
                    break
            for line in Path("/proc/meminfo").read_text().splitlines():
                if line.startswith("MemTotal:"):
                    memory = int(line.split()[1]) * 1024
                    break
        except (OSError, ValueError):
            pass
    return {"platform": platform.platform(), "machine": platform.machine(), "processor": cpu,
            "logical_cpus": os.cpu_count(), "physical_memory_bytes": memory}


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--cells", type=lambda v: _bounded_int(v, MAX_CELLS), default=8192,
                        help="actual contiguous natural-cell queries (max: 262144)")
    parser.add_argument("--minutes", type=lambda v: _bounded_int(v, 120), default=5,
                        help="actual shared-clock minutes (max: 120)")
    parser.add_argument("--seconds", type=float, default=MAX_SECONDS, help="child timeout, at most 30 seconds")
    parser.add_argument("--memory-mib", type=lambda v: _bounded_int(v, 1024), default=1024,
                        help="child memory budget, at most 1024 MiB")
    args = parser.parse_args()
    if not 0 < args.seconds <= MAX_SECONDS:
        parser.error("--seconds must be positive and at most 30")
    executable = godot.find_godot()
    if executable is None:
        print("Godot not found; run python tools/godot.py doctor", file=sys.stderr)
        return 1
    command = [str(executable), "--headless", "--path", str(ROOT), "--script", WORKER,
               "--", str(args.cells), str(args.minutes)]
    try:
        result = run_guarded(command, args.seconds, args.memory_mib * 1024**2)
    except (OSError, RuntimeError, ValueError) as exc:
        print(f"Cannot safely run benchmark: {exc}", file=sys.stderr)
        return 1
    payload = _parse_worker(result)
    if result["status"] == "success" and payload is None:
        result["status"] = "invalid_worker_output"
    report = {
        "format_version": 1, "created_utc": datetime.now(timezone.utc).isoformat(),
        "hardware": _host_metadata(),
        "godot_version": godot.godot_version(executable),
        "supervisor": result, "worker": payload,
    }
    directory = ROOT / "logs" / "benchmarks"
    directory.mkdir(parents=True, exist_ok=True)
    (ROOT / "logs" / ".gdignore").touch(exist_ok=True)
    path = directory / f"world_{time.time_ns()}.json"
    with path.open("x", encoding="utf-8") as handle:
        json.dump(report, handle, indent=2, ensure_ascii=False)
        handle.write("\n")
    print(json.dumps({"status": result["status"], "report": str(path), "worker": payload}, ensure_ascii=False))
    return 0 if result["status"] == "success" else 1


if __name__ == "__main__":
    raise SystemExit(main())
