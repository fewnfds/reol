#!/usr/bin/env python3
"""Summarize rendered captures and align actual Windows thread CPU to them."""
from __future__ import annotations

import argparse
from collections import defaultdict
import json
from pathlib import Path


def summarize(path: Path) -> dict:
    report = json.loads(path.read_text(encoding="utf-8"))
    crowd = report.get("crowd", {})
    result = {
        "report": str(path), "revision": report.get("revision"),
        "artifact_sha256": report.get("artifact_sha256"),
        "actors": crowd.get("actors"), "complex": crowd.get("complex", {}),
        "workers": report.get("actor_execution", {}).get("home", {}).get("configured_workers"),
        "capture_seconds": report.get("capture_seconds"),
        "rate": report.get("achieved_fraction"), "frame_ms": report.get("frame_ms"),
        "input_probe": report.get("input_probe"), "host": report.get("simulation_host"),
        "body_publication": report.get("body_publication_capture"),
        "environment": crowd.get("environment_compute"),
        "environment_response": crowd.get("environment_response_compute"),
        "publication_including_setup": report.get("publication_work_including_setup"),
        "errors": report.get("world_errors"),
    }
    sidecar = path.with_suffix(".cpu.json")
    if sidecar.is_file():
        cpu = json.loads(sidecar.read_text(encoding="utf-8"))
        start, end = report["capture_started_unix"], report["capture_finished_unix"]
        totals: dict[str, float] = defaultdict(float)
        memory, covered = 0, 0.0
        for row in cpu["samples"]:
            elapsed = row["elapsed_seconds"]
            overlap = max(0.0, min(end, row["unix_seconds"]) - max(start, row["unix_seconds"] - elapsed))
            if elapsed <= 0 or overlap <= 0:
                continue
            covered += overlap
            for tid, seconds in row["thread_cpu_seconds"].items():
                totals[tid] += seconds * overlap / elapsed
            memory = max(memory, row["private_bytes"])
        names = cpu.get("thread_names", {})
        main = str(cpu.get("main_thread_id", ""))
        result["cpu"] = {
            "scope": "capture overlap; partial 0.5s samples weighted by overlap, approximate at edges",
            "covered_seconds": covered, "cpu_seconds": sum(totals.values()),
            "mean_executing_cores": sum(totals.values()) / covered if covered else None,
            "main_cpu_seconds": totals.get(main), "peak_private_mib": memory / 1024**2,
            "top_threads": [{"id": tid, "name": names.get(tid, ""), "cpu_seconds": seconds,
                             "main": tid == main} for tid, seconds in sorted(totals.items(), key=lambda pair: -pair[1])[:12]],
        }
    return result


def main() -> None:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("reports", type=Path, nargs="+")
    args = parser.parse_args()
    print(json.dumps([summarize(path) for path in args.reports], ensure_ascii=False, indent=2))


if __name__ == "__main__":
    main()
