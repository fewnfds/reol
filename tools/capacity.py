#!/usr/bin/env python3
"""Check feature cost against history, with at most three release windows per speed."""
from __future__ import annotations

import argparse
import hashlib
import json
import math
import os
from pathlib import Path
import platform
import statistics
import time

import benchmark
import godot


def hardware() -> dict:
    cpu = platform.processor()
    if os.name == "nt":
        import winreg
        with winreg.OpenKey(winreg.HKEY_LOCAL_MACHINE, r"HARDWARE\DESCRIPTION\System\CentralProcessor\0") as key:
            cpu = winreg.QueryValueEx(key, "ProcessorNameString")[0].strip()
    return {"cpu": cpu, "logical_cpus": os.cpu_count()}


def load_reference(path: Path) -> dict:
    data = json.loads(path.read_text(encoding="utf-8"))
    if data.get("format") not in {"reol-performance-baseline-v1", "reol-performance-check-v1"} or data.get("scenario") != "capacity-v1":
        raise ValueError("Expected a portable baseline or a completed feature-check summary")
    if data.get("status", "complete") != "complete" or not data.get("samples"):
        raise ValueError("Reference must contain completed, usable measured samples")
    for sample in data["samples"]:
        if sample["speed"] not in [1, 2, 4, 8, 16] or not 150 <= sample["actors"] <= 60000 or not 5 <= sample["seconds"] <= 60:
            raise ValueError("Reference speed/population/window is outside the supported workload")
        for name in ["step_mean_ms", "process_mean_ms", "gpu_mean_ms", "frame_mean_ms", "frame_p99_ms"]:
            if not math.isfinite(sample[name]) or sample[name] < 0:
                raise ValueError("Reference contains invalid timing data")
    return data


def metrics(report: dict, seconds: int) -> dict:
    return {"speed": report["requested_speed"], "actors": report["actors"], "seconds": seconds,
            "actual_speed": report["actual_speed"], "step_mean_ms": report["step_mean_ms"],
            "process_mean_ms": report["process_ms"]["mean"], "gpu_mean_ms": report["gpu_ms"]["mean"],
            "frame_mean_ms": report["frame_ms"]["mean"], "frame_p99_ms": report["frame_ms"]["p99"]}


def capacity_view(camera: dict) -> bool:
    return (isinstance(camera, dict) and camera.get("position") == [7040, 7040]
            and math.isclose(camera.get("zoom", 0), .21, abs_tol=.00001))


def classify(report: dict, args: argparse.Namespace) -> dict:
    """A collapsed workload is invalid evidence, rather than a slow CPU result."""
    reasons = []
    if report.get("capture_exit_code", 1) or not report.get("release"):
        reasons.append("capture_failed_or_not_release")
    if report.get("scenario") != "capacity-v1" or report.get("fog") is not False or not capacity_view(report.get("camera")):
        reasons.append("workload_or_view_changed")
    for name in ["actual_speed", "requested_speed", "actors", "wall_seconds", "world_delta_ms", "moved_cells_delta", "step_mean_ms"]:
        value = report.get(name)
        if not isinstance(value, (int, float)) or not math.isfinite(value) or value <= 0:
            reasons.append("invalid_" + name)
    for name in ["frame_ms", "activity_fraction", "process_ms", "gpu_ms"]:
        value = report.get(name, {}).get("mean")
        if not isinstance(value, (int, float)) or not math.isfinite(value) or value < 0:
            reasons.append("invalid_" + name)
    tail = report.get("frame_ms", {}).get("p99")
    if not isinstance(tail, (int, float)) or not math.isfinite(tail) or tail < 0:
        reasons.append("invalid_frame_p99")
    if reasons:
        return {"valid": False, "reasons": reasons}
    if report.get("material") != report.get("initial_material") or report.get("alive", 0) < report["actors"] or report["activity_fraction"]["mean"] < args.min_activity:
        return {"valid": False, "reasons": ["workload_died_idle_or_not_conserved"]}
    ratio = report["actual_speed"] / report["requested_speed"]
    if ratio > 1.05:
        return {"valid": False, "reasons": ["clock_ratio_above_tolerance"]}
    segments = report.get("segments", [])
    sim = (ratio >= args.min_ratio and report.get("overload_demand_usec_delta", math.inf) <= 0
           and len(segments) == 2 and all(s.get("actual_speed", 0) / report["requested_speed"] >= args.min_ratio for s in segments))
    fps = 1000 / max(.001, report["frame_ms"]["mean"])
    return {"valid": True, "simulation": sim, "speed_ratio": ratio, "mean_fps": fps,
            "playable": sim and fps >= args.min_fps and report["frame_ms"].get("p99", math.inf) <= args.p99_ms}


class Check:
    def __init__(self, args: argparse.Namespace):
        self.args = args
        self.reference = load_reference(args.baseline)
        self.points = {sample["speed"]: sample for sample in self.reference["samples"]}
        if any(speed not in self.points for speed in args.speeds):
            raise ValueError("No history for a requested speed; supply --baseline with that speed")
        self.out = args.out.resolve()
        self.out.mkdir(parents=True, exist_ok=False)
        self.identities = {p: hashlib.sha256(p.read_bytes()).hexdigest() for p in [args.binary, args.binary.with_suffix(".pck")]}
        self.result = {"format": "reol-performance-check-v1", "status": "running", "scenario": "capacity-v1",
                       "started": time.strftime("%Y-%m-%dT%H:%M:%S%z"), "baseline": str(args.baseline),
                       "pack_sha256": self.identities[args.binary.with_suffix(".pck")], "hardware": hardware(),
                       "config": {"fps": args.fps, "workers": args.workers, "fog": False,
                                  "camera": {"zoom": .21, "position": [7040, 7040]}},
                       "criteria": {key: str(value) if isinstance(value, Path) else value for key, value in vars(args).items()},
                       "trials": [], "results": [], "samples": []}
        self.save()

    def save(self) -> None:
        temporary = self.out / "summary.tmp"
        temporary.write_text(json.dumps(self.result, ensure_ascii=False, indent=2), encoding="utf-8")
        temporary.replace(self.out / "summary.json")
        lines = ["# 本次功能性能对照", "", f"状态：{self.result['status']}；参考：{self.args.baseline}。",
                 f"每倍率最多{self.args.max_trials}次；先测历史同人数，有退化再复测或降档，不精确搜索极限。", "",
                 "| 倍率 | 历史人数 | 本次通过 / 未通过人数 | 同人数步耗时变化 | 判读 |", "|---|---:|---|---|---|"]
        labels = {"acceptable": "参考范围内", "review_cost": "成本增加，需权衡", "capacity_regressed": "原负载未达标",
                  "variable": "结果波动", "not_comparable": "条件不同，仅作新样本", "invalid": "负载/采样失效"}
        for row in self.result["results"]:
            delta = row.get("step_change_pct")
            lines.append(f"| {row['speed']:g}× | {row['reference_actors']} | {row['pass']} / {row['fail']} | "
                         f"{f'{delta:+.1f}%' if delta is not None else '—'} | {labels[row['verdict']]} |")
        lines += ["", "通过指世界流速和画面均达到本次判据；人数是少量探测，不是精确最大值。",
                  "同人数、同采样时长及硬件/视图/worker条件才能比较成本。实际倍率、主线程/GPU成本差、失效原因见summary.json。",
                  "成本变化是短窗观察，不隔离系统噪声或场景工作量变化；历史不会被本次结果自动覆盖。"]
        (self.out / "report.md").write_text("\n".join(lines) + "\n", encoding="utf-8")

    def compare(self, sample: dict, reference: dict, renderer: str) -> dict:
        same_host = all(self.result["hardware"].get(key) == self.reference["hardware"].get(key) for key in ["cpu", "logical_cpus"])
        if (not same_host or renderer != self.reference["hardware"].get("renderer")
                or any(self.result["config"][key] != self.reference["config"].get(key) for key in ["fps", "workers", "fog"])
                or not capacity_view(self.reference["config"].get("camera"))
                or any(sample[key] != reference[key] for key in ["speed", "actors", "seconds"])):
            return {"comparable": False, "reason": "hardware_config_population_or_window_changed"}
        changes = {name: (sample[name] / reference[name] - 1) * 100
                   for name in ["step_mean_ms", "process_mean_ms", "gpu_mean_ms", "frame_mean_ms", "frame_p99_ms"] if reference[name] > 0}
        return {"comparable": True, "change_pct": changes}

    def measure(self, speed: float, actors: int) -> dict:
        if any(hashlib.sha256(p.read_bytes()).hexdigest() != digest for p, digest in self.identities.items()):
            raise RuntimeError("Release binary/pack changed during the check")
        seconds = self.args.seconds or self.points[speed]["seconds"]
        name = f"{len(self.result['trials']) + 1:02}-{speed:g}x-{actors}"
        print(f"PERF_START {name} {seconds}s", flush=True)
        report = benchmark.capture(binary=self.args.binary, actors=actors, speed=speed, fps=self.args.fps,
                                   workers=self.args.workers, seconds=seconds, gpu_index=self.args.gpu_index,
                                   output=self.out / (name + ".json"), capacity=True, fog=False)
        # The binary hash is the build identity; git describes the surrounding workspace.
        self.result["source_commit"] = report.get("git_commit", "")
        check = classify(report, self.args)
        if check["valid"] and (report["actors"] != actors or report["requested_speed"] != speed):
            check = {"valid": False, "reasons": ["requested_configuration_mismatch"]}
        trial = {"speed": speed, "actors": actors, "file": name + ".json", "classification": check}
        if check["valid"]:
            trial["metrics"] = metrics(report, seconds)
            trial["comparison"] = self.compare(trial["metrics"], self.points[speed], report["renderer"])
            self.result["hardware"]["renderer"] = report["renderer"]
        self.result["trials"].append(trial)
        self.save()
        print("PERF_RESULT " + json.dumps(trial, ensure_ascii=False), flush=True)
        return trial

    def check_speed(self, speed: float) -> None:
        reference = self.points[speed]
        actors = reference["actors"]
        trials = []
        for attempt in range(self.args.max_trials):
            trial = self.measure(speed, actors)
            trials.append(trial)
            check = trial["classification"]
            if not check["valid"]:
                break
            if not check["playable"]:
                smaller = max(150, int(actors * min(.8, check["speed_ratio"] * .9)) // 50 * 50)
                if smaller >= actors:
                    break
                actors = smaller
            elif attempt == 0 and trial["comparison"].get("change_pct", {}).get("step_mean_ms", 0) > self.args.regression_pct:
                continue  # One same-load repeat checks a suspicious cost increase.
            else:
                break
        valid = [t for t in trials if t["classification"]["valid"]]
        anchors = [t for t in valid if t["actors"] == reference["actors"]]
        changes = [t["comparison"]["change_pct"]["step_mean_ms"] for t in anchors if t["comparison"]["comparable"]]
        delta = statistics.median(changes) if changes else None
        passing = [t["actors"] for t in valid if t["classification"]["playable"]]
        failing = [t["actors"] for t in valid if not t["classification"]["playable"]]
        anchor_passes = sum(t["classification"]["playable"] for t in anchors)
        verdict = "acceptable"
        if len(valid) != len(trials): verdict = "invalid"
        elif delta is None: verdict = "not_comparable"
        elif not anchor_passes: verdict = "capacity_regressed"
        elif anchor_passes < len(anchors): verdict = "variable"
        elif delta > self.args.regression_pct: verdict = "review_cost"
        self.result["results"].append({"speed": speed, "reference_actors": reference["actors"],
            "historical_next_failed_actors": reference.get("next_failed_actors"), "pass": max(passing, default=None),
            "fail": min(failing, default=None), "step_change_pct": delta, "verdict": verdict, "captures": len(trials)})
        if passing:
            best = max((t for t in valid if t["classification"]["playable"]), key=lambda t: t["actors"])
            self.result["samples"].append(best["metrics"] | {"evidence": best["file"]})
        self.save()

    def run(self) -> None:
        try:
            for speed in self.args.speeds:
                self.check_speed(speed)
            self.result["status"] = "complete"
        except BaseException as exc:
            self.result["status"] = "interrupted" if isinstance(exc, KeyboardInterrupt) else "failed"
            self.result["error"] = str(exc)
            raise
        finally:
            self.result["finished"] = time.strftime("%Y-%m-%dT%H:%M:%S%z")
            self.save()


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--binary", type=Path, default=godot.ROOT / "build/windows/reol-demo.exe")
    parser.add_argument("--baseline", type=Path, default=godot.ROOT / "docs/status/performance.json")
    parser.add_argument("--out", type=Path, default=godot.ROOT / "logs" / ("performance-" + time.strftime("%Y%m%d-%H%M%S")))
    parser.add_argument("--speeds", type=int, nargs="+", choices=[1, 2, 4, 8, 16], default=[1, 2, 4, 8, 16])
    parser.add_argument("--max-trials", type=int, choices=[1, 2, 3], default=3)
    parser.add_argument("--seconds", type=int, help="default: match each historical window")
    parser.add_argument("--regression-pct", type=float, default=15, help="cost increase worth reviewing, not automatic rejection")
    parser.add_argument("--min-ratio", type=float, default=.98)
    parser.add_argument("--min-fps", type=float, default=57)
    parser.add_argument("--p99-ms", type=float, default=33.34)
    parser.add_argument("--min-activity", type=float, default=.5)
    parser.add_argument("--fps", type=int, default=60)
    parser.add_argument("--gpu-index", type=int, default=1)
    parser.add_argument("--workers", type=int, default=-1)
    args = parser.parse_args()
    args.binary, args.baseline = args.binary.resolve(), args.baseline.resolve()
    args.speeds = list(dict.fromkeys(args.speeds))
    if not args.binary.is_file() or not args.binary.with_suffix(".pck").is_file():
        parser.error("export the Windows Demo binary and pack first")
    if args.seconds is not None and not 5 <= args.seconds <= 60:
        parser.error("seconds must be 5..60")
    if not (10 <= args.fps <= 240 and -1 <= args.workers <= 64 and .9 <= args.min_ratio <= 1
            and 1 <= args.min_fps <= args.fps and 0 <= args.min_activity <= 1
            and math.isfinite(args.p99_ms) and args.p99_ms > 0 and math.isfinite(args.regression_pct) and args.regression_pct >= 0):
        parser.error("invalid FPS, workers or comparison criteria")
    try:
        check = Check(args)
    except (OSError, ValueError, KeyError) as error:
        parser.error(str(error))
    check.run()
    print(check.out / "report.md", flush=True)
    return int(any(row["verdict"] == "invalid" for row in check.result["results"]))


if __name__ == "__main__":
    raise SystemExit(main())
