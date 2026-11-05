#!/usr/bin/env python3
"""Run one bounded real-ground CPU/GPU benchmark in its own Godot process.

Use identical side/radii options in separate sequential CPU and GPU runs.
Default uses the project's native renderer, needed for a real GPU; --headless
is useful for CPU/fallback only. Memory/time limits protect this child process
and do not define a game-wide budget.
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
MAX_MEMORY_MIB = 12 * 1024
MARKER = "ENV_GROUND_COMPUTE_BENCHMARK "
WORKER = "res://tools/benchmarks/environment_ground_compute.gd"


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
    parser.add_argument("--backend", choices=("cpu", "gpu", "auto"), default="cpu")
    parser.add_argument("--seconds", type=float, default=300.0)
    parser.add_argument("--memory-mib", type=int, default=4096)
    parser.add_argument("--no-changes", action="store_true")
    parser.add_argument("--headless", action="store_true")
    parser.add_argument("--adapter-contains", help="require this text in the reported adapter name")
    args = parser.parse_args()
    if not 0 < args.seconds <= MAX_SECONDS:
        parser.error(f"--seconds must be positive and <= {MAX_SECONDS:g}")
    if not 1 <= args.memory_mib <= MAX_MEMORY_MIB:
        parser.error(f"--memory-mib must be between 1 and {MAX_MEMORY_MIB}")
    executable = godot.find_godot()
    if executable is None:
        print("Godot not found; run python tools/godot.py doctor", file=sys.stderr)
        return 1
    command = [str(executable)]
    if args.headless:
        command.append("--headless")
    command += ["--path", str(ROOT), "--script", WORKER, "--", "--side", str(args.side),
                "--radii", args.radii, "--backend", args.backend]
    if args.no_changes:
        command.append("--no-changes")
    # Temporarily adjust only this launcher process's bounds; never alter the
    # shared module on disk or terminate anything except the owned child job.
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
    elif payload is not None:
        jobs = [("initial_field", payload.get("initial_field", {}))]
        changes = payload.get("changes", {})
        for name in ("local_1", "local_16", "local_64", "scattered_1_percent"):
            change = changes.get(name, {}) if isinstance(changes, dict) else {}
            for operation in ("removed_compute", "restore_compute"):
                if isinstance(change, dict) and operation in change:
                    jobs.append((f"{name}/{operation}", change[operation]))
        if args.backend == "gpu":
            fallback = next(((name, job) for name, job in jobs if job.get("actual_backend") != "gpu"), None)
            if fallback is not None:
                result["status"] = "gpu_fallback"
                result["error"] = f"{fallback[0]}: {fallback[1].get('fallback_reason', 'unknown')}"
        if result["status"] == "success" and args.adapter_contains and args.adapter_contains.casefold() not in str(payload.get("adapter", "")).casefold():
            result["status"] = "adapter_mismatch"
            result["error"] = f"requested {args.adapter_contains!r}; actual {payload.get('adapter', '')!r}"
        if result["status"] == "success" and args.backend == "gpu" and args.adapter_contains:
            mismatch = next(((name, job) for name, job in jobs if args.adapter_contains.casefold()
                             not in str(job.get("gpu", {}).get("device", "")).casefold()), None)
            if mismatch is not None:
                result["status"] = "adapter_mismatch"
                result["error"] = f"{mismatch[0]} worker device does not match {args.adapter_contains!r}"
    sources = (
        "project.godot",
        "data/definitions/environment_sources.json",
        "scripts/sim/environment_ground_cache.gd",
        "scripts/sim/environment_field_cache.gd",
        "scripts/sim/environment_source_bindings.gd",
        "scripts/sim/environment_field_rules.gd",
        "scripts/sim/object_lifecycle.gd",
        "scripts/runtime/environment_field_compute_runtime.gd",
        "scripts/runtime/environment_field_gpu.gd",
        "assets/shaders/environment_field_compute.glsl",
        "tools/benchmarks/environment_ground_cache.gd",
        "tools/benchmarks/environment_ground_compute.gd",
        "tests/sim/test_regional_simulation.gd",
    )
    report = {
        "format_version": 1,
        "created_utc": datetime.now(timezone.utc).isoformat(),
        "hardware": guard._host_metadata(),
        "godot_version": godot.godot_version(executable),
        "arguments": vars(args),
        "supervisor": result,
        "worker": payload,
        "source": {
            "head": subprocess.run(["git", "rev-parse", "HEAD"], cwd=ROOT, capture_output=True, text=True, check=True).stdout.strip(),
            "status": subprocess.run(["git", "status", "--short"], cwd=ROOT, capture_output=True, text=True, check=True).stdout,
            "sha256": {name: hashlib.sha256((ROOT / name).read_bytes()).hexdigest() for name in sources},
        },
    }
    directory = ROOT / "logs" / "benchmarks"
    directory.mkdir(parents=True, exist_ok=True)
    (ROOT / "logs" / ".gdignore").touch(exist_ok=True)
    path = directory / f"environment_ground_compute_{args.side}_{args.radii}_{args.backend}_{time.time_ns()}.json"
    with path.open("x", encoding="utf-8") as handle:
        json.dump(report, handle, indent=2, ensure_ascii=False)
        handle.write("\n")
    print(json.dumps({"status": result["status"], "error": result["error"], "report": str(path), "worker": payload}, ensure_ascii=False))
    return 0 if result["status"] == "success" else 1


if __name__ == "__main__":
    raise SystemExit(main())
