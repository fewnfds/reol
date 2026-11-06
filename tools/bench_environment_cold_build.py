#!/usr/bin/env python3
"""Run the real-ground CPU cold-build benchmark under an owned process guard.

This is an offline developer benchmark, not a rendered game or GPU test. Each
run gets a fresh report and limits only the child process tree. A report records
the exact measured scripts and source state; compare identical options/hardware.
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

ROOT = Path(__file__).resolve().parents[1]
sys.path.insert(0, str(ROOT / "tools"))
import godot  # noqa: E402
import world_benchmark as guard  # noqa: E402

MAX_SECONDS = 1800.0
MAX_MEMORY_MIB = 12 * 1024
MARKER = "ENV_COLD_BUILD_BENCHMARK "
WORKER = "res://tools/bench_environment_cold_build.gd"
FINGERPRINTS = (
    "project.godot", "data/definitions/environment_sources.json",
    "scripts/data/environment_source_definitions.gd",
    "scripts/sim/environment_field_rules.gd",
    "scripts/sim/environment_field_cache.gd",
    "scripts/sim/environment_ground_field.gd",
    "scripts/sim/environment_ground_cache.gd",
    "scripts/sim/environment_source_bindings.gd",
    "scripts/sim/object_lifecycle.gd",
    "scripts/sim/object_receipts.gd",
    "scripts/sim/ground_placements.gd",
    "scripts/sim/inventory_ledger.gd",
    "scripts/sim/regional_simulation.gd",
    "tests/sim/test_object_lifecycle.gd",
    "tools/bench_environment_cold_build.gd",
    "tools/bench_environment_cold_build.py",
)


def parse_payload(result: dict) -> tuple[dict | None, str]:
    """Fail closed on missing/duplicated marker, script errors, or bad JSON."""
    if result.get("output_truncated"):
        return None, "output_truncated"
    lines = result.get("output", "").splitlines()
    if any(line.lstrip().startswith(("SCRIPT ERROR:", "ERROR:")) for line in lines):
        return None, "engine_error_output"
    found = [line.removeprefix(MARKER) for line in lines if line.startswith(MARKER)]
    if len(found) != 1:
        return None, "marker_count"
    try:
        payload = json.loads(found[0])
    except json.JSONDecodeError:
        return None, "invalid_json"
    if not isinstance(payload, dict) or payload.get("benchmark") != "environment_cold_build":
        return None, "invalid_payload"
    return payload, ""


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--size", type=int, choices=(64, 128, 512), default=64)
    parser.add_argument("--work", type=int, default=4096)
    parser.add_argument("--usec", type=int, default=2000)
    parser.add_argument("--distribution", choices=("uniform", "mixed"), default="uniform")
    parser.add_argument("--seconds", type=float, default=900.0)
    parser.add_argument("--memory-mib", type=int, default=10240)
    parser.add_argument("--output", type=Path, help="new JSON report path; never overwrites an existing file")
    args = parser.parse_args()
    if not 0 < args.seconds <= MAX_SECONDS:
        parser.error(f"--seconds must be positive and <= {MAX_SECONDS:g}")
    if not 1 <= args.memory_mib <= MAX_MEMORY_MIB:
        parser.error(f"--memory-mib must be between 1 and {MAX_MEMORY_MIB}")
    if not 1 <= args.work <= 100000 or not 1 <= args.usec <= 100000:
        parser.error("--work and --usec must each be between 1 and 100000")
    executable = godot.find_godot()
    if executable is None:
        print("Godot not found; run python tools/godot.py doctor", file=sys.stderr)
        return 1
    output = args.output
    if output is None:
        directory = ROOT / "logs" / "benchmarks"
        directory.mkdir(parents=True, exist_ok=True)
        (ROOT / "logs" / ".gdignore").touch(exist_ok=True)
        output = directory / f"environment_cold_build_{args.size}_{args.distribution}_{time.time_ns()}.json"
    # Reserve the report before starting the long process. Existing paths and
    # absent parent directories fail rather than risking overwrite or data loss.
    try:
        with output.open("x", encoding="utf-8") as handle:
            handle.write('{"status":"in_progress"}\n')
    except OSError as exc:
        print(f"Cannot create fresh report: {exc}", file=sys.stderr)
        return 1
    command = [str(executable), "--headless", "--path", str(ROOT), "--script", WORKER, "--",
               f"--size={args.size}", f"--work={args.work}", f"--usec={args.usec}",
               f"--distribution={args.distribution}"]
    guard.MAX_SECONDS = MAX_SECONDS
    guard.MAX_BYTES = MAX_MEMORY_MIB * 1024**2
    try:
        result = guard.run_guarded(command, args.seconds, args.memory_mib * 1024**2)
    except (OSError, RuntimeError, ValueError) as exc:
        report = {"format_version": 1, "status": "guard_error", "error": str(exc)}
        output.write_text(json.dumps(report, ensure_ascii=False, indent=2) + "\n", encoding="utf-8")
        print(json.dumps({"status": "guard_error", "error": str(exc), "report": str(output)}, ensure_ascii=False))
        return 1
    payload, payload_error = parse_payload(result)
    success = result.get("status") == "success" and payload is not None and payload.get("ok") is True
    if result.get("status") == "success" and not success:
        result["status"] = "invalid_worker_output"
    arguments = vars(args).copy()
    arguments["output"] = str(args.output) if args.output is not None else None
    report = {
        "format_version": 1,
        "created_utc": datetime.now(timezone.utc).isoformat(),
        "hardware": guard._host_metadata(),
        "godot_version": godot.godot_version(executable),
        "arguments": arguments,
        "supervisor": result,
        "worker": payload,
        "payload_error": payload_error,
        "source": {
            "head": subprocess.run(["git", "rev-parse", "HEAD"], cwd=ROOT,
                                   capture_output=True, text=True, check=True).stdout.strip(),
            "status": subprocess.run(["git", "status", "--short"], cwd=ROOT,
                                     capture_output=True, text=True, check=True).stdout,
            "sha256": {name: hashlib.sha256((ROOT / name).read_bytes()).hexdigest() for name in FINGERPRINTS},
        },
    }
    with output.open("w", encoding="utf-8") as handle:
        json.dump(report, handle, indent=2, ensure_ascii=False)
        handle.write("\n")
    print(json.dumps({"status": result.get("status"), "error": result.get("error"),
                      "payload_error": payload_error, "report": str(output), "worker": payload}, ensure_ascii=False))
    return 0 if success else 1


if __name__ == "__main__":
    raise SystemExit(main())
