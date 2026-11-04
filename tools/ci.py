#!/usr/bin/env python3
"""Low-frequency, shared-cache GitHub Actions observation; no model poll loop.

status prints one observation. wait uses the same cache and sleeps in this
process, printing only status changes and the terminal result. All callers in
this checkout share the five-minute throttle, including after a network error.
"""

from __future__ import annotations

import argparse
import hashlib
import json
import os
from pathlib import Path
import re
import subprocess
import sys
import time
from typing import Callable

ROOT = Path(__file__).resolve().parents[1]
MIN_INTERVAL_SECONDS = 300


class CIError(RuntimeError):
    pass


def query_run(repo: str, run_id: int) -> dict:
    try:
        result = subprocess.run(
            ["gh", "run", "view", str(run_id), "--repo", repo, "--json",
             "databaseId,headSha,status,conclusion,url"],
            capture_output=True, text=True, encoding="utf-8", errors="replace",
            timeout=45, check=False,
        )
    except (OSError, subprocess.TimeoutExpired) as exc:
        raise CIError(f"GitHub query failed: {type(exc).__name__}") from exc
    if result.returncode:
        raise CIError(f"gh run view failed (exit {result.returncode}); check gh auth/network.")
    try:
        return json.loads(result.stdout)
    except ValueError as exc:
        raise CIError("GitHub returned invalid JSON.") from exc


class RunMonitor:
    def __init__(self, cache_dir: Path, repo: str, run_id: int, sha: str, *,
                 query: Callable[[str, int], dict] | None = None,
                 now: Callable[[], float] = time.time,
                 sleep: Callable[[float], None] = time.sleep):
        if not re.fullmatch(r"[A-Za-z0-9_.-]+/[A-Za-z0-9_.-]+", repo):
            raise CIError("Repository must be OWNER/REPO.")
        if run_id <= 0 or not re.fullmatch(r"[0-9a-fA-F]{40}", sha):
            raise CIError("Use a positive run ID and the full 40-character commit SHA.")
        self.repo, self.run_id, self.sha = repo, run_id, sha.lower()
        self.query, self.now, self.sleep = query or query_run, now, sleep
        cache_dir.mkdir(parents=True, exist_ok=True)
        key = hashlib.sha256(repo.lower().encode()).hexdigest()[:16]
        self.path = cache_dir / f"{key}-{run_id}.json"
        self.lock_path = self.path.with_suffix(".lock")

    def _read(self) -> dict:
        try:
            return json.loads(self.path.read_text(encoding="utf-8"))
        except FileNotFoundError:
            return {}
        except (OSError, ValueError) as exc:
            raise CIError(f"Invalid CI cache: {self.path}; inspect it before retrying.") from exc

    def _write(self, data: dict) -> None:
        temporary = self.path.with_suffix(".tmp")
        temporary.write_text(json.dumps(data, ensure_ascii=False, indent=2), encoding="utf-8")
        temporary.replace(self.path)

    def _validate(self, state: dict) -> None:
        if (not isinstance(state, dict) or state.get("headSha", "").lower() != self.sha
                or state.get("databaseId") != self.run_id):
            raise CIError("Run ID or commit SHA mismatch; this run cannot verify the requested code.")
        if state.get("status") not in {"queued", "in_progress", "completed", "waiting", "pending", "requested"}:
            raise CIError("GitHub returned an unknown run status.")

    def poll(self) -> dict:
        # Kernel-owned lock: crashes release it automatically. Keep the path in
        # place; unlinking a locked inode would let a new caller bypass it.
        descriptor = os.open(self.lock_path, os.O_CREAT | os.O_RDWR, 0o600)
        try:
            if os.name == "nt":
                import msvcrt
                msvcrt.locking(descriptor, msvcrt.LK_NBLCK, 1)
            else:
                import fcntl
                fcntl.flock(descriptor, fcntl.LOCK_EX | fcntl.LOCK_NB)
        except OSError as exc:
            os.close(descriptor)
            raise CIError(f"CI query already owned by another process: {self.lock_path}") from exc
        try:
            metadata = json.dumps({"pid": os.getpid(), "created_at": self.now()}).encode()
            os.lseek(descriptor, 0, os.SEEK_SET)
            os.write(descriptor, metadata)
            os.ftruncate(descriptor, len(metadata))
            cached = self._read()
            state = cached.get("state", {})
            if state:
                self._validate(state)
            if state.get("status") == "completed":
                return {"cached": True, "next_poll_in": 0, "state": state}
            current = self.now()
            delay = max(0.0, float(cached.get("last_attempt", -MIN_INTERVAL_SECONDS))
                        + MIN_INTERVAL_SECONDS - current)
            if delay > 0:
                return {"cached": True, "next_poll_in": delay, "state": state,
                        "error": cached.get("error", "")}
            cached["last_attempt"] = current
            cached.pop("error", None)
            # Record the attempt before touching the network: failures are also
            # throttled, so retrying cannot become an expensive model loop.
            self._write(cached)
            try:
                state = self.query(self.repo, self.run_id)
                self._validate(state)
            except Exception as exc:
                cached["error"] = type(exc).__name__
                self._write(cached)
                if isinstance(exc, CIError):
                    raise
                raise CIError(f"GitHub query failed: {type(exc).__name__}") from exc
            cached["state"] = state
            self._write(cached)
            return {"cached": False, "next_poll_in": MIN_INTERVAL_SECONDS,
                    "state": state}
        finally:
            os.close(descriptor)

    def wait(self, timeout: float) -> int:
        if timeout <= 0:
            raise CIError("Timeout must be positive.")
        deadline = self.now() + timeout
        last_status = None
        while True:
            if last_status is not None and self.now() >= deadline:
                print("CI wait timed out; run is not verified.", file=sys.stderr)
                return 2
            observed = self.poll()
            state = observed["state"]
            status = (state.get("status", "unknown"), state.get("conclusion", ""))
            if status != last_status:
                print(json.dumps(observed, ensure_ascii=False), flush=True)
                last_status = status
            if state.get("status") == "completed":
                return 0 if state.get("conclusion") == "success" else 1
            if observed.get("error"):
                raise CIError("Previous query failed; retry once after the reported cooldown.")
            remaining = deadline - self.now()
            if remaining <= 0:
                print("CI wait timed out; run is not verified.", file=sys.stderr)
                return 2
            self.sleep(min(max(1.0, observed["next_poll_in"]), remaining))


def main(argv: list[str] | None = None) -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("operation", choices=["status", "wait"])
    parser.add_argument("--run", type=int, required=True)
    parser.add_argument("--sha", required=True)
    parser.add_argument("--repo", default="fewnfds/reol")
    parser.add_argument("--timeout", type=int, default=3000, help="wait limit in seconds (default 3000)")
    args = parser.parse_args(argv)
    try:
        monitor = RunMonitor(ROOT / "logs" / "ci", args.repo, args.run, args.sha)
        if args.operation == "wait":
            return monitor.wait(args.timeout)
        print(json.dumps(monitor.poll(), ensure_ascii=False), flush=True)
        return 0
    except (CIError, OSError) as exc:
        print(f"CI: {exc}", file=sys.stderr)
        return 2
    except KeyboardInterrupt:
        print("CI observation stopped; the GitHub run continues.", file=sys.stderr)
        return 130


if __name__ == "__main__":
    raise SystemExit(main())
