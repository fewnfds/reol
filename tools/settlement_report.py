#!/usr/bin/env python3
"""Read existing NORMAL_SETTLEMENT logs; never run or mutate the simulation.

Reports differences between observed cumulative samples, not time since zero.
A parsed SMOKE marker is not an independently observed process exit code.
"""
from __future__ import annotations

import argparse
import hashlib
import json
from pathlib import Path
import re
import sys


MARKER = "NORMAL_SETTLEMENT "
TERMINAL = re.compile(r"^SETTLEMENT_CYCLE_(SMOKE|PARTIAL) errors=(\d+)(?=\s|$)")
COUNTERS = ("actions", "refusals", "generated", "metrics")
ITEMS = ("grain", "meal", "water")
METRICS = ("decisions", "observations", "decision_usec", "observe_usec", "step_usec",
           "environment_usec", "units_usec", "perception_usec", "unit_decision_usec",
           "navigation_geometry_usec", "navigation_search_usec")


def integer(value: object, name: str, minimum: int | None = None) -> int:
    if type(value) is not int or (minimum is not None and value < minimum):
        raise ValueError(f"{name}: expected integer" + (f" >= {minimum}" if minimum is not None else ""))
    return value


def counts(value: object, name: str) -> dict[str, int]:
    if not isinstance(value, dict):
        raise ValueError(f"{name}: missing counter/stock map")
    for key, amount in value.items():
        if not isinstance(key, str) or not key:
            raise ValueError(f"{name}: expected nonempty keys")
        integer(amount, f"{name}.{key}", 0)
    return value


def vitals(value: object, name: str) -> list[int]:
    if not isinstance(value, list) or not value:
        raise ValueError(f"{name}: missing sampled values")
    for amount in value:
        integer(amount, name)
    return value


def validate(sample: object) -> dict:
    if not isinstance(sample, dict):
        raise ValueError("snapshot must be an object")
    integer(sample.get("at_ms"), "at_ms", 0)
    for key in (*COUNTERS, "items"):
        counts(sample.get(key), key)
    for name, required in (("items", ITEMS), ("metrics", METRICS)):
        if not set(required).issubset(sample[name]):
            raise ValueError(f"{name}: missing fixed fields from settlement_cycle_smoke")
    if set(sample["metrics"]) != set(METRICS):
        raise ValueError("metrics: unsupported fields; classify new counters/gauges before analyzing")
    lowest = sample.get("lowest_sampled")
    if not isinstance(lowest, dict):
        raise ValueError("lowest_sampled: missing sample map")
    for key in ("satiety", "energy"):
        vitals(sample.get(key), key)
        low = lowest.get(key)
        if not isinstance(low, dict):
            raise ValueError(f"lowest_sampled.{key}: missing sample")
        integer(low.get("actor"), f"lowest_sampled.{key}.actor", 0)
        integer(low.get("value"), f"lowest_sampled.{key}.value")
    districts = sample.get("districts")
    if not isinstance(districts, list) or not districts:
        raise ValueError("districts: missing or empty list")
    names: set[str] = set()
    for district in districts:
        if not isinstance(district, dict):
            raise ValueError("districts: expected objects")
        name = district.get("name")
        if not isinstance(name, str) or not name or name in names:
            raise ValueError("districts: missing or duplicate name")
        names.add(name)
        for key in ("actions", "items"):
            counts(district.get(key), f"districts.{name}.{key}")
        if not set(ITEMS).issubset(district["items"]):
            raise ValueError(f"districts.{name}.items: missing fixed stock fields")
        for key in ("satiety", "energy"):
            vitals(district.get(key), f"districts.{name}.{key}")
    return sample


def difference(before: dict, after: dict, name: str, *, cumulative: bool = True) -> dict:
    result = {key: after.get(key, 0) - before.get(key, 0) for key in sorted(before.keys() | after.keys())}
    if cumulative and any(value < 0 for value in result.values()):
        raise ValueError(f"{name}: cumulative counter went backwards; separate runs or changed schemas")
    return result


def interval(before: dict, after: dict) -> dict:
    a, b = before["snapshot"], after["snapshot"]
    duration = b["at_ms"] - a["at_ms"]
    if duration <= 0:
        raise ValueError("at_ms must increase; separate concatenated runs")
    wall_ms = None
    if before["wall_ms"] is not None and after["wall_ms"] is not None:
        wall_ms = after["wall_ms"] - before["wall_ms"]
        if wall_ms < 0:
            raise ValueError("wall_ms went backwards; do not join restarted processes")
    output = {"from_ms": a["at_ms"], "to_ms": b["at_ms"], "simulation_ms": duration,
              "wall_ms": wall_ms,
              "simulation_to_wall_ratio": duration / wall_ms if wall_ms else None}
    for key in COUNTERS:
        output[key + "_delta"] = difference(a[key], b[key], key)
    output["items_delta"] = difference(a["items"], b["items"], "items", cumulative=False)
    output["completed_per_sim_minute"] = {key: value * 60000 / duration
                                          for key, value in output["actions_delta"].items()}
    old_districts = {value["name"]: value for value in a["districts"]}
    new_districts = {value["name"]: value for value in b["districts"]}
    if old_districts.keys() != new_districts.keys():
        raise ValueError("district membership changed; incompatible log schema")
    output["districts"] = {}
    for name, district in new_districts.items():
        previous = old_districts[name]
        output["districts"][name] = {
            "resident_actions_delta": difference(previous["actions"], district["actions"], f"{name}.actions"),
            "spatial_items_delta": difference(previous["items"], district["items"], f"{name}.items", cumulative=False),
            "satiety_at_end": district["satiety"], "energy_at_end": district["energy"]}
    # lowest_sampled is cumulative since the test's own start/checkpoint. It
    # cannot locate a low point within this particular interval.
    output["satiety_at_end"] = b["satiety"]
    output["energy_at_end"] = b["energy"]
    output["lowest_sampled_through_end"] = b["lowest_sampled"]
    return output


def reject_constant(value: str) -> None:
    raise ValueError(f"non-finite JSON number: {value}")


def unique_keys(pairs: list[tuple]) -> dict:
    result = {}
    for key, value in pairs:
        if key in result:
            raise ValueError(f"duplicate JSON key: {key}")
        result[key] = value
    return result


def analyze(content: str) -> dict:
    samples = []
    windows = []
    terminal = {"kind": "absent", "reported_errors": None, "line": None}
    diagnostics = []
    decoder = json.JSONDecoder(parse_constant=reject_constant, object_pairs_hook=unique_keys)
    for number, line in enumerate(content.splitlines(), 1):
        if line.lstrip().startswith(("SCRIPT ERROR:", "USER ERROR:", "ERROR:", "FAIL ")):
            diagnostics.append({"line": number, "message": line.strip()})
        end = TERMINAL.match(line)
        if line.startswith(("SETTLEMENT_CYCLE_SMOKE", "SETTLEMENT_CYCLE_PARTIAL")) and not end:
            raise ValueError(f"line {number}: malformed terminal marker")
        if end:
            if terminal["kind"] != "absent":
                raise ValueError(f"line {number}: multiple terminal markers; supply one run")
            terminal = {"kind": "smoke" if end[1] == "SMOKE" else "partial",
                        "reported_errors": int(end[2]), "line": number}
        if not line.startswith(MARKER):
            continue
        try:
            if terminal["kind"] != "absent":
                raise ValueError("snapshot after terminal marker; supply one run")
            tail = line[len(MARKER):]
            data, offset = decoder.raw_decode(tail)
            suffix = tail[offset:].strip()
            match = re.fullmatch(r"wall_ms=(\d+)", suffix) if suffix else None
            if suffix and match is None:
                raise ValueError("expected only wall_ms after snapshot JSON")
            sample = {"line": number, "wall_ms": int(match[1]) if match else None,
                      "snapshot": validate(data)}
            if samples:
                windows.append(interval(samples[-1], sample))
            samples.append(sample)
        except (ValueError, TypeError, AttributeError) as error:
            raise ValueError(f"line {number}: {error}") from error
    if not samples:
        raise ValueError("no NORMAL_SETTLEMENT snapshots (short runs may not reach a reporting boundary)")
    return {"format": "reol-settlement-report-1", "sample_count": len(samples),
            "terminal": terminal, "process_exit_code": None, "diagnostics": diagnostics,
            "first_sample": samples[0], "last_sample": samples[-1],
            "observed_span": interval(samples[0], samples[-1]) if len(samples) > 1 else None,
            "windows": windows,
            "limits": ["Only intervals between printed samples; no assumed time-zero baseline or missing samples.",
                       "A smoke/partial marker is reported text, not an observed process exit or new acceptance.",
                       "Terminal final dictionaries are not parsed; the last sample may precede the actual stop.",
                       "Actions are completed result counts, not labor time or opportunities; refusals include interruptions.",
                       "Refusals come from activity_results, not every unchosen or rejected planning candidate.",
                       "District actions/vitals group assigned residents; stocks group current object positions, not ownership.",
                       "Stocks are sampled; lowest_sampled may predate this log window or resume.",
                       "Build, opening, seed, stepping and worker conditions need separate provenance before comparing runs.",
                       "Wall time includes the test's own audits, checkpoint writes and in-process restoration checks.",
                       "Timing counters can overlap; no CPU utilization, FPS, queue age or individual fairness is inferred."]}


def main(argv: list[str] | None = None) -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("log", type=Path, help="one settlement_cycle_smoke log; no concatenated processes")
    parser.add_argument("--output", type=Path, help="write a new JSON report; default stdout")
    args = parser.parse_args(argv)
    try:
        raw = args.log.read_bytes()
        report = analyze(raw.decode("utf-8-sig"))
        report["source"] = {"path": str(args.log.resolve()), "sha256": hashlib.sha256(raw).hexdigest()}
        rendered = json.dumps(report, ensure_ascii=False, indent=2, allow_nan=False) + "\n"
        if args.output is None:
            print(rendered, end="")
        else:
            # A report is never permitted to replace the source or an earlier
            # artifact, including through an alias/symlink to that file.
            with args.output.open("x", encoding="utf-8") as destination:
                destination.write(rendered)
    except (OSError, UnicodeError, ValueError) as error:
        print(f"settlement_report: {error}", file=sys.stderr)
        return 2
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
