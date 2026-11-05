#!/usr/bin/env python3
"""Run one offline real-owner cache benchmark with a bounded owned process.

The guard reuses tools/world_benchmark.py's Windows job / Linux RLIMIT and
memory sampler. The extended limits apply only to this launcher process.
Example:
  python tools/benchmarks/environment_ground_cache_guard.py --side 64 --seconds 180 --memory-mib 2048
Run each size sequentially; do not run alongside the complete Godot suite.
"""

from __future__ import annotations

import argparse
import hashlib
import json
import subprocess
import sys
import time
from datetime import datetime, timezone
from pathlib import Path

ROOT = Path(__file__).resolve().parents[2]
sys.path.insert(0, str(ROOT / "tools"))
import godot  # noqa: E402
import world_benchmark as guard  # noqa: E402

MAX_SECONDS = 1800.0
MAX_MEMORY_MIB = 8192
MARKER = "ENV_GROUND_CACHE_BENCHMARK "
WORKER = "res://tools/benchmarks/environment_ground_cache.gd"


def _payload(result: dict) -> dict | None:
    if result["status"] != "success" or result["output_truncated"]:
        return None
    lines = result["output"].splitlines()
    if any(line.lstrip().startswith(("SCRIPT ERROR:", "ERROR:")) for line in lines):
        return None
    payloads = [line.removeprefix(MARKER) for line in lines if line.startswith(MARKER)]
    if len(payloads) != 1:
        return None
    try:
        payload = json.loads(payloads[0])
    except json.JSONDecodeError:
        return None
    return payload if isinstance(payload, dict) and payload.get("ok") is True else None


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--side", type=int, choices=(64, 128, 256, 512), default=64)
    parser.add_argument("--radii", choices=("max", "mixed"), default="max")
    parser.add_argument("--seconds", type=float, default=180.0)
    parser.add_argument("--memory-mib", type=int, default=2048)
    parser.add_argument("--no-full-field", action="store_true")
    parser.add_argument("--no-changes", action="store_true")
    args = parser.parse_args()
    if not 0 < args.seconds <= MAX_SECONDS:
        parser.error(f"--seconds must be positive and <= {MAX_SECONDS:g}")
    if not 1 <= args.memory_mib <= MAX_MEMORY_MIB:
        parser.error(f"--memory-mib must be between 1 and {MAX_MEMORY_MIB}")
    executable = godot.find_godot()
    if executable is None:
        print("Godot not found; run python tools/godot.py doctor", file=sys.stderr)
        return 1
    command = [str(executable), "--headless", "--path", str(ROOT), "--script", WORKER,
               "--", "--side", str(args.side), "--radii", args.radii]
    if args.no_full_field:
        command.append("--no-full-field")
    if args.no_changes:
        command.append("--no-changes")
    # run_guarded enforces these module-level caps before creating a child.
    # Raising them in this short-lived launcher does not modify the shared
    # module on disk or the ordinary benchmark's 30-second / 1-GiB limits.
    guard.MAX_SECONDS = MAX_SECONDS
    guard.MAX_BYTES = MAX_MEMORY_MIB * 1024**2
    try:
        result = guard.run_guarded(command, args.seconds, args.memory_mib * 1024**2)
    except (OSError, RuntimeError, ValueError) as exc:
        print(f"Cannot safely run benchmark: {exc}", file=sys.stderr)
        return 1
    payload = _payload(result)
    if result["status"] == "success" and payload is None:
        result["status"] = "invalid_worker_output"
    report = {
        "format_version": 1,
        "created_utc": datetime.now(timezone.utc).isoformat(),
        "hardware": guard._host_metadata(),
        "godot_version": godot.godot_version(executable),
        "supervisor": result,
        "worker": payload,
        "source": {
            "head": subprocess.run(["git", "rev-parse", "HEAD"], cwd=ROOT, capture_output=True, text=True, check=True).stdout.strip(),
            "status": subprocess.run(["git", "status", "--short"], cwd=ROOT, capture_output=True, text=True, check=True).stdout,
            "sha256": {
                name: hashlib.sha256((ROOT / name).read_bytes()).hexdigest()
                for name in (
                    "scripts/sim/environment_ground_cache.gd",
                    "scripts/sim/environment_field_cache.gd",
                    "scripts/sim/environment_source_bindings.gd",
                    "scripts/sim/environment_field_rules.gd",
                    "scripts/sim/object_lifecycle.gd",
                    "tools/benchmarks/environment_ground_cache.gd",
                )
            },
        },
    }
    directory = ROOT / "logs" / "benchmarks"
    directory.mkdir(parents=True, exist_ok=True)
    (ROOT / "logs" / ".gdignore").touch(exist_ok=True)
    path = directory / f"environment_ground_cache_{args.side}_{args.radii}_{time.time_ns()}.json"
    with path.open("x", encoding="utf-8") as handle:
        json.dump(report, handle, indent=2, ensure_ascii=False)
        handle.write("\n")
    print(json.dumps({"status": result["status"], "report": str(path), "worker": payload}, ensure_ascii=False))
    return 0 if result["status"] == "success" else 1


if __name__ == "__main__":
    raise SystemExit(main())
