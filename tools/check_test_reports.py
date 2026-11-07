#!/usr/bin/env python3
"""Verify that successful CI shards completed the whole Godot test registry.

Worker exit codes and Godot log error gates must also pass. This checks coverage
and timing records; a report alone cannot certify an engine's exit status.
"""

from __future__ import annotations

import argparse
import json
import math
from pathlib import Path


class ReportError(ValueError):
    pass


def _require(condition: bool, message: str) -> None:
    if not condition:
        raise ReportError(message)


def _count(value: object) -> bool:
    return type(value) is int and value >= 0


def _names(value: object) -> bool:
    return (isinstance(value, list) and bool(value)
            and all(isinstance(name, str) and name.startswith("test_") for name in value)
            and value == sorted(set(value)))


def verify_reports(paths: list[Path], shards: int) -> dict:
    _require(shards > 0 and len(paths) == shards, f"Expected {shards} reports, found {len(paths)}")
    registry: list[str] | None = None
    covered: set[str] = set()
    indices: set[int] = set()
    timings: dict[int, float] = {}
    total_checks = 0
    for path in paths:
        events = [json.loads(line) for line in path.read_text(encoding="utf-8").splitlines() if line.strip()]
        _require(bool(events) and all(isinstance(event, dict) for event in events), f"Invalid events in {path}")
        start, finish = events[0], events[-1]
        _require(start.get("event") == "run_started" and finish.get("event") == "run_finished", f"Incomplete run: {path}")
        names, selected = start.get("registered_suites"), start.get("suites")
        _require(_names(names) and _names(selected), f"Invalid registry or selection: {path}")
        _require(type(start.get("registered_count")) is int and start["registered_count"] == len(names), f"Registry count differs: {path}")
        if registry is None:
            registry = names
        _require(registry == names, f"Shards disagree about the registry: {path}")
        index = start.get("shard_index")
        _require(type(index) is int and 1 <= index <= shards and index not in indices, f"Invalid/duplicate shard: {path}")
        _require(type(start.get("shard_count")) is int and start["shard_count"] == shards, f"Shard count differs: {path}")
        _require(selected == names[index - 1::shards], f"Shard selection differs from the complete registry: {path}")
        _require(len(events) == 2 * len(selected) + 2, f"Missing or extra suite events: {path}")
        checks, elapsed = 0, 0.0
        for position, name in enumerate(selected):
            begun, ended = events[1 + 2 * position:3 + 2 * position]
            _require(begun.get("event") == "suite_started" and begun.get("suite") == name, f"Suite start differs: {path}")
            _require(ended.get("event") == "suite_finished" and ended.get("suite") == name, f"Suite did not finish: {path}")
            _require(_count(ended.get("checks")) and type(ended.get("assertion_failures")) is int and ended["assertion_failures"] == 0, f"Invalid counts or failed assertions: {path}")
            duration = ended.get("elapsed_ms")
            _require(type(duration) in (float, int) and math.isfinite(duration) and duration >= 0, f"Invalid timing: {path}")
            checks += ended["checks"]
            elapsed += duration
        _require(type(finish.get("passed")) is int and finish["passed"] == len(selected)
                 and type(finish.get("failed")) is int and finish["failed"] == 0
                 and type(finish.get("checks")) is int and finish["checks"] == checks, f"Run totals differ or failed: {path}")
        _require(not covered.intersection(selected), f"Duplicate suite coverage: {path}")
        covered.update(selected)
        indices.add(index)
        total_checks += checks
        timings[index] = elapsed
    _require(registry is not None and covered == set(registry), "Some registered suites were omitted")
    return {"suites": len(covered), "checks": total_checks, "shard_ms": timings}


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("directory", type=Path)
    parser.add_argument("--shards", type=int, required=True)
    args = parser.parse_args()
    try:
        result = verify_reports(sorted(args.directory.rglob("check-test-timings-*.jsonl")), args.shards)
    except (ReportError, OSError, ValueError) as exc:
        parser.exit(1, f"Test coverage verification failed: {exc}\n")
    print(f"Coverage verified: {result['suites']} suites, {result['checks']} checks across {args.shards} shards")
    for index, elapsed in sorted(result["shard_ms"].items()):
        print(f"  shard {index}: {elapsed / 1000:.3f}s of suite execution")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
