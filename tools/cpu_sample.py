"""Bounded Windows per-thread CPU/memory sampling for owned performance runs.

GetThreadTimes measures CPU execution, unlike frame/worker elapsed timers.
No extra package, debugger attachment, or polling from the agent is needed.
"""
from __future__ import annotations

import ctypes as c
from ctypes import wintypes as w
import json
import os
from pathlib import Path
import threading
import time


class ProcessSample:
    def __init__(self, path: Path):
        self.path = path
        self.rows: list[dict] = []
        self.thread_names: dict[int, str] = {}
        self.main_thread: int | None = None
        self._stop = threading.Event()
        self._thread: threading.Thread | None = None

    def start(self, pid: int) -> None:
        if os.name == "nt":
            self._thread = threading.Thread(target=self._run, args=(pid,), daemon=True)
            self._thread.start()

    def close(self) -> None:
        self._stop.set()
        if self._thread:
            self._thread.join(timeout=3)
        self.path.write_text(json.dumps({"format": "windows_thread_cpu_v1",
            "logical_processors": os.cpu_count(), "interval_seconds": 0.5,
            "scope": "owned process including assembly; timestamps allow capture-only selection; CPU seconds are kernel+user, not elapsed time",
            "main_thread_id": self.main_thread, "thread_names": self.thread_names,
            "samples": self.rows}, indent=2), encoding="utf-8")

    def _run(self, pid: int) -> None:
        kernel = c.WinDLL("kernel32", use_last_error=True)
        psapi = c.WinDLL("psapi", use_last_error=True)

        class Entry(c.Structure):
            _fields_ = [("size", w.DWORD), ("usage", w.DWORD), ("tid", w.DWORD),
                        ("pid", w.DWORD), ("base", w.LONG), ("delta", w.LONG), ("flags", w.DWORD)]

        class Memory(c.Structure):
            _fields_ = [("size", w.DWORD), ("faults", w.DWORD)] + [
                (key, c.c_size_t) for key in ("peak_working", "working", "peak_paged", "paged",
                "peak_nonpaged", "nonpaged", "pagefile", "peak_pagefile", "private")]

        kernel.CreateToolhelp32Snapshot.argtypes = [w.DWORD, w.DWORD]
        kernel.CreateToolhelp32Snapshot.restype = w.HANDLE
        kernel.Thread32First.argtypes = kernel.Thread32Next.argtypes = [w.HANDLE, c.POINTER(Entry)]
        kernel.OpenThread.argtypes = [w.DWORD, w.BOOL, w.DWORD]
        kernel.OpenThread.restype = w.HANDLE
        kernel.OpenProcess.argtypes = [w.DWORD, w.BOOL, w.DWORD]
        kernel.OpenProcess.restype = w.HANDLE
        kernel.CloseHandle.argtypes = [w.HANDLE]
        kernel.GetThreadTimes.argtypes = [w.HANDLE] + [c.POINTER(w.FILETIME)] * 4
        kernel.GetThreadDescription.argtypes = [w.HANDLE, c.POINTER(c.c_wchar_p)]
        kernel.GetThreadDescription.restype = w.LONG
        kernel.LocalFree.argtypes = [c.c_void_p]
        psapi.GetProcessMemoryInfo.argtypes = [w.HANDLE, c.POINTER(Memory), w.DWORD]
        process = kernel.OpenProcess(0x1000 | 0x10, False, pid)
        previous: dict[int, float] = {}
        last = time.perf_counter()
        try:
            while not self._stop.is_set():
                current: dict[int, float] = {}
                creation: dict[int, int] = {}
                snapshot = kernel.CreateToolhelp32Snapshot(4, 0)
                if snapshot and snapshot != c.c_void_p(-1).value:
                    entry = Entry()
                    entry.size = c.sizeof(entry)
                    valid = kernel.Thread32First(snapshot, c.byref(entry))
                    while valid:
                        if entry.pid == pid:
                            handle = kernel.OpenThread(0x0800, False, entry.tid)
                            if handle:
                                values = [w.FILETIME() for _ in range(4)]
                                if kernel.GetThreadTimes(handle, *[c.byref(t) for t in values]):
                                    current[entry.tid] = sum((t.dwHighDateTime << 32) + t.dwLowDateTime for t in values[2:]) / 1e7
                                    creation[entry.tid] = (values[0].dwHighDateTime << 32) + values[0].dwLowDateTime
                                description = c.c_wchar_p()
                                if kernel.GetThreadDescription(handle, c.byref(description)) == 0:
                                    if description.value:
                                        self.thread_names[entry.tid] = description.value
                                    kernel.LocalFree(c.cast(description, c.c_void_p))
                                kernel.CloseHandle(handle)
                        valid = kernel.Thread32Next(snapshot, c.byref(entry))
                    kernel.CloseHandle(snapshot)
                now = time.perf_counter()
                if self.main_thread is None and creation:
                    self.main_thread = min(creation, key=creation.get)
                memory = Memory()
                memory.size = c.sizeof(memory)
                psapi.GetProcessMemoryInfo(process, c.byref(memory), memory.size)
                self.rows.append({"unix_seconds": time.time(), "elapsed_seconds": now - last,
                    "thread_cpu_seconds": {str(tid): max(0, value - previous[tid]) for tid, value in current.items() if tid in previous},
                    "working_bytes": memory.working, "private_bytes": memory.private})
                previous, last = current, now
                self._stop.wait(0.5)
        finally:
            if process:
                kernel.CloseHandle(process)
