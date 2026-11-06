#!/usr/bin/env python3
"""Run the real-ground continuous-response benchmark in one bounded child.

Reports a single offline headless result with working/private memory sampled by
world_benchmark. Limits apply only to this owned child, not to the game budget.
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
MARKER = "ENV_RESPONSE_GROUND_BENCHMARK "
WORKER = "res://tools/bench_environment_response.gd"


def payload_from(result: dict) -> dict | None:
    if result["status"] != "success" or result["output_truncated"]:
        return None
    lines = result["output"].splitlines()
    if any(line.lstrip().startswith(("SCRIPT ERROR:", "ERROR:")) for line in lines):
        return None
    found = [line.removeprefix(MARKER) for line in lines if line.startswith(MARKER)]
    if len(found) != 1:
        return None
    try:
        payload = json.loads(found[0])
    except json.JSONDecodeError:
        return None
    return payload if isinstance(payload, dict) and payload.get("ok") is True else None


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--size", type=int, choices=(64, 128, 512), default=64)
    parser.add_argument("--events", type=int, choices=(1, 8, 32), default=1)
    parser.add_argument("--field-work", type=int, default=128)
    parser.add_argument("--cell-budget", type=int, default=32)
    parser.add_argument("--snapshot", action="store_true")
    parser.add_argument("--seconds", type=float, default=900.0)
    parser.add_argument("--memory-mib", type=int, default=10240)
    args = parser.parse_args()
    if not 0 < args.seconds <= MAX_SECONDS:
        parser.error(f"--seconds must be positive and <= {MAX_SECONDS:g}")
    if not 1 <= args.memory_mib <= MAX_MEMORY_MIB:
        parser.error(f"--memory-mib must be between 1 and {MAX_MEMORY_MIB}")
    if not 1 <= args.field_work <= 100000 or not 1 <= args.cell_budget <= 256:
        parser.error("invalid field-work or cell-budget")
    executable = godot.find_godot()
    if executable is None:
        print("Godot not found; run python tools/godot.py doctor", file=sys.stderr)
        return 1
    command = [str(executable), "--headless", "--path", str(ROOT), "--script", WORKER, "--",
               f"--size={args.size}", f"--events={args.events}",
               f"--field-work={args.field_work}", f"--cell-budget={args.cell_budget}"]
    if args.snapshot:
        command.append("--snapshot")
    guard.MAX_SECONDS = MAX_SECONDS
    guard.MAX_BYTES = MAX_MEMORY_MIB * 1024**2
    try:
        result = guard.run_guarded(command, args.seconds, args.memory_mib * 1024**2)
    except (OSError, RuntimeError, ValueError) as exc:
        print(f"Cannot safely run benchmark: {exc}", file=sys.stderr)
        return 1
    payload = payload_from(result)
    if result["status"] == "success" and payload is None:
        result["status"] = "invalid_worker_output"
    files = (
        "project.godot", "data/definitions/environment_sources.json",
        "scripts/sim/environment_ground_cache.gd", "scripts/sim/environment_source_change.gd",
        "scripts/sim/environment_source_bindings.gd", "scripts/sim/environment_temperature_state.gd",
        "scripts/sim/environment_phase_state.gd", "scripts/sim/environment_response_targets.gd",
        "scripts/sim/environment_ground_field.gd", "scripts/sim/environment_target_compiler.gd",
        "scripts/sim/object_lifecycle.gd", "scripts/sim/object_actions.gd", "scripts/sim/object_receipts.gd",
        "scripts/sim/ground_placements.gd", "scripts/sim/inventory_ledger.gd",
        "scripts/sim/regional_simulation.gd", "scripts/runtime/environment_response_session.gd",
        "scripts/persistence/environment_response_snapshot.gd", "tools/bench_environment_response.gd",
        "scripts/persistence/environment_response_columns.gd", "scripts/persistence/environment_response_file.gd",
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
            "head": subprocess.run(["git", "rev-parse", "HEAD"], cwd=ROOT,
                                   capture_output=True, text=True, check=True).stdout.strip(),
            "status": subprocess.run(["git", "status", "--short"], cwd=ROOT,
                                     capture_output=True, text=True, check=True).stdout,
            "sha256": {name: hashlib.sha256((ROOT / name).read_bytes()).hexdigest() for name in files},
        },
    }
    directory = ROOT / "logs" / "benchmarks"
    directory.mkdir(parents=True, exist_ok=True)
    (ROOT / "logs" / ".gdignore").touch(exist_ok=True)
    path = directory / f"environment_response_{args.size}_{args.events}_{time.time_ns()}.json"
    with path.open("x", encoding="utf-8") as handle:
        json.dump(report, handle, indent=2, ensure_ascii=False)
        handle.write("\n")
    print(json.dumps({"status": result["status"], "error": result["error"],
                      "report": str(path), "worker": payload}, ensure_ascii=False))
    return 0 if result["status"] == "success" else 1


if __name__ == "__main__":
    raise SystemExit(main())
