#!/usr/bin/env python3
"""Serial release-window capacity search for 1/2/4/8/16x; incremental JSON + Markdown."""
from __future__ import annotations

import argparse
import hashlib
import json
import math
from pathlib import Path
import platform
import time

import benchmark
import godot


def classify(report: dict, args: argparse.Namespace) -> dict:
    """Invalid/collapsed workloads are not evidence of a CPU capacity failure."""
    invalid = []
    if report.get("capture_exit_code", 1):
        invalid.append("capture_failed")
    if report.get("scenario") != "capacity-v1" or not report.get("release"):
        invalid.append("wrong_workload_or_debug_build")
    camera = report.get("camera", {})
    if report.get("fog") is not False or not isinstance(camera, dict) or not math.isclose(camera.get("zoom", 0), .21, abs_tol=.00001) or camera.get("position") != [7040, 7040]:
        invalid.append("view_configuration_changed")
    for field in ["actual_speed", "requested_speed", "actors", "wall_seconds", "world_delta_ms", "moved_cells_delta"]:
        if not isinstance(report.get(field), (int, float)) or not math.isfinite(report[field]) or report[field] <= 0:
            invalid.append("invalid_" + field)
    for field in ["frame_ms", "activity_fraction"]:
        if not isinstance(report.get(field), dict) or not isinstance(report[field].get("mean"), (int, float)) or not math.isfinite(report[field]["mean"]):
            invalid.append("invalid_" + field)
    if invalid:
        return {"valid": False, "reasons": invalid}
    if report.get("material") != report.get("initial_material"):
        invalid.append("material_not_conserved")
    if report.get("alive", 0) < report["actors"]:
        invalid.append("population_died")
    if report["activity_fraction"]["mean"] < args.min_activity:
        invalid.append("activity_below_floor")
    if invalid:
        return {"valid": False, "reasons": invalid}
    ratio = report["actual_speed"] / report["requested_speed"]
    if ratio > 1.05:
        return {"valid": False, "reasons": ["clock_ratio_above_tolerance"]}
    fps = 1000 / max(.001, report["frame_ms"]["mean"])
    sim = ratio >= args.min_ratio and report.get("overload_demand_usec_delta", math.inf) <= 0
    segments = report.get("segments", [])
    if len(segments) != 2 or any(segment.get("actual_speed", 0) / report["requested_speed"] < args.min_ratio for segment in segments):
        sim = False
    return {"valid": True, "simulation": sim,
            "playable": sim and fps >= args.min_fps and report["frame_ms"].get("p99", math.inf) <= args.p99_ms,
            "speed_ratio": ratio, "mean_fps": fps, "activity": report["activity_fraction"]["mean"]}


class Search:
    def __init__(self, args: argparse.Namespace):
        self.args = args
        self.out = args.out.resolve()
        self.out.mkdir(parents=True, exist_ok=False)
        self.cache: dict[tuple, dict] = {}
        self.hints: dict[tuple, tuple[int, int | None]] = {}
        if args.seed_report:
            previous = json.loads(args.seed_report.read_text(encoding="utf-8"))
            for speed in args.speeds:
                for metric in ["simulation", "playable"]:
                    points = [trial for trial in previous.get("trials", []) if trial.get("speed") == speed
                              and trial.get("classification", {}).get("valid") and isinstance(trial.get("actors"), int)
                              and args.minimum <= trial["actors"] <= args.maximum]
                    low = max((t["actors"] for t in points if t["classification"].get(metric)), default=0)
                    high = min((t["actors"] for t in points if not t["classification"].get(metric) and t["actors"] > low), default=None)
                    if low:
                        self.hints[speed, metric] = low, high
        self.result = {"format": "reol-capacity-v1", "status": "running", "scenario": "capacity-v1",
                       "started": time.strftime("%Y-%m-%dT%H:%M:%S%z"), "hardware": platform.platform(),
                       "criteria": vars(args) | {"binary": str(args.binary.resolve()), "out": str(self.out), "seed_report": str(args.seed_report.resolve()) if args.seed_report else None},
                       "trials": [], "limits": []}
        self.identities = {p: hashlib.sha256(p.read_bytes()).hexdigest() for p in [args.binary.resolve(), args.binary.resolve().with_suffix(".pck")]}
        self.save()

    def save(self):
        # Each trial is already on disk; atomically replace the small searchable summary.
        tmp = self.out / "summary.tmp"
        tmp.write_text(json.dumps(self.result, ensure_ascii=False, indent=2), encoding="utf-8")
        tmp.replace(self.out / "summary.json")
        lines = ["# 自动容量测量", "", f"状态：{self.result['status']}。负载 capacity-v1，1280×720，全视图，真实 release 窗口串行运行。", "",
                 f"满倍率：全窗及前后半窗实际/请求 ≥ {self.args.min_ratio:.1%}，无新增追赶需求截断。流畅档另要求平均 ≥ {self.args.min_fps:g} FPS、帧时 P99 ≤ {self.args.p99_ms:g} ms。", "",
                 "| 倍率 | 口径 | 已确认通过人数 | 已确认不通过人数 | 结果 |", "|---|---|---:|---:|---|"]
        for limit in self.result["limits"]:
            lines.append(f"| {limit['speed']:g}× | {limit['metric']} | {limit.get('pass', '—')} | {limit.get('fail', '—')} | {limit['status']} |")
        lines += ["", "人数是这一场景、硬件和阈值下的实测区间；非所有玩法的普遍极限，短窗不代表长局稳定性。", "",
                  "50 个房间、静态/移动环境、100 名交战者与20名长工期施工请求者，其余自主取放/观察/探索；初始生命/需求及木料充足，约两成单位穿戴测试装备。", "",
                  "失效、死亡、物资不守恒或平均忙碌比例低于阈值的窗口不参与极限判定。每次试验 JSON、CPU 样本和日志均保留；确认窗更长。"]
        (self.out / "report.md").write_text("\n".join(lines) + "\n", encoding="utf-8")

    def measure(self, speed: float, actors: int, confirm: bool = False) -> dict:
        seconds = self.args.confirm_seconds if confirm else self.args.seconds
        key = speed, actors, seconds
        if key in self.cache:
            return self.cache[key]
        # Never compare measurements from an executable changed mid-search.
        if any(hashlib.sha256(p.read_bytes()).hexdigest() != digest for p, digest in self.identities.items()):
            raise RuntimeError("Release binary/pack changed during the search")
        number = len(self.result["trials"]) + 1
        name = f"{number:03}-{speed:g}x-{actors}-{'confirm' if confirm else 'search'}"
        print(f"CAPACITY_START {name} {seconds}s", flush=True)
        report = benchmark.capture(binary=self.args.binary, actors=actors, speed=speed, fps=self.args.fps,
                                   workers=self.args.workers, seconds=seconds, gpu_index=self.args.gpu_index,
                                   output=self.out / (name + ".json"), capacity=True, fog=False)
        check = classify(report, self.args)
        if report.get("actors") != actors or report.get("requested_speed") != speed:
            check = {"valid": False, "reasons": ["requested_configuration_mismatch"]}
        trial = {"speed": speed, "actors": actors, "seconds": seconds, "confirm": confirm,
                 "file": name + ".json", "classification": check}
        self.result["trials"].append(trial)
        self.cache[key] = trial
        self.save()
        print("CAPACITY_RESULT " + json.dumps(trial, ensure_ascii=False), flush=True)
        if not check["valid"]:
            raise RuntimeError(f"Invalid window {name}: {check['reasons']}; inspect its log/metrics")
        return trial

    def search(self, speed: float, metric: str) -> dict:
        minimum, maximum, resolution = self.args.minimum, self.args.maximum, self.args.resolution
        low, high = 0, None
        hint = self.hints.get((speed, metric))
        if hint:
            # An old report provides candidate populations only. Both endpoints
            # are measured afresh in long windows on the current frozen pack.
            for point in [p for p in hint if p is not None]:
                if self.measure(speed, point, True)["classification"][metric]:
                    low = point
                else:
                    high = point
                    break
        else:
            point = min(maximum, max(minimum, self.args.start))
            # Bracket first; cache is shared by criteria, never by different rates.
            while True:
                trial = self.measure(speed, point)
                if trial["classification"][metric]:
                    low = point
                    if point == maximum:
                        break
                    point = min(maximum, point * 2)
                else:
                    high = point
                    break
            while high is not None and high - low > resolution:
                point = max(minimum, (low + high) // 2 // resolution * resolution)
                if point <= low or point >= high:
                    break
                if self.measure(speed, point)["classification"][metric]:
                    low = point
                else:
                    high = point
        # Independent longer windows establish final bounds. If warm hardware
        # invalidates the short bracket, refine using long windows, with a hard cap.
        for _ in range(18):
            if low and not self.measure(speed, low, True)["classification"][metric]:
                high, low = low, 0
            if high is not None and self.measure(speed, high, True)["classification"][metric]:
                low, high = high, None
            if high is None:
                if low == maximum:
                    return {"speed": speed, "metric": metric, "pass": low, "fail": None, "status": "configured_cap_reached"}
                point = min(maximum, max(minimum, low + max(resolution, math.ceil(low * .1)) if hint else low * 2))
            elif high - low <= resolution or high <= minimum:
                return {"speed": speed, "metric": metric, "pass": low, "fail": high,
                        "status": "below_minimum" if not low else "confirmed_interval"}
            else:
                point = max(minimum, (low + high) // 2 // resolution * resolution)
                if point <= low or point >= high:
                    return {"speed": speed, "metric": metric, "pass": low, "fail": high, "status": "confirmed_interval"}
            if self.measure(speed, point, True)["classification"][metric]:
                low = point
            else:
                high = point
        return {"speed": speed, "metric": metric, "pass": low, "fail": high, "status": "no_stable_bracket"}

    def run(self) -> None:
        try:
            for speed in self.args.speeds:
                for metric in ["simulation", "playable"]:
                    self.result["limits"].append(self.search(speed, metric))
                    self.save()
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
    parser.add_argument("--out", type=Path, default=godot.ROOT / "logs" / ("capacity-" + time.strftime("%Y%m%d-%H%M%S")))
    parser.add_argument("--speeds", type=float, nargs="+", default=[1, 2, 4, 8, 16])
    parser.add_argument("--start", type=int, default=500)
    parser.add_argument("--seed-report", type=Path, help="old summary: candidate populations only, all results remeasured on this build")
    parser.add_argument("--minimum", type=int, default=150)
    parser.add_argument("--maximum", type=int, default=60000)
    parser.add_argument("--resolution", type=int, default=100)
    parser.add_argument("--seconds", type=int, default=10)
    parser.add_argument("--confirm-seconds", type=int, default=25)
    parser.add_argument("--min-ratio", type=float, default=.98)
    parser.add_argument("--min-fps", type=float, default=57)
    parser.add_argument("--p99-ms", type=float, default=33.34)
    parser.add_argument("--min-activity", type=float, default=.5)
    parser.add_argument("--fps", type=int, default=60)
    parser.add_argument("--gpu-index", type=int, default=1)
    parser.add_argument("--workers", type=int, default=-1)
    args = parser.parse_args()
    if not args.binary.is_file() or not args.binary.with_suffix(".pck").is_file():
        parser.error("export the Windows Demo binary and pack first")
    if not (150 <= args.minimum <= args.start <= args.maximum <= 60000 and 1 <= args.resolution <= args.maximum and 5 <= args.seconds < args.confirm_seconds <= 60 and 10 <= args.fps <= 240 and -1 <= args.workers <= 64):
        parser.error("population 150..60000; positive resolution; 5 <= seconds < confirm-seconds <= 60; FPS 10..240; workers -1..64")
    numeric = args.speeds + [args.min_ratio, args.min_fps, args.p99_ms, args.min_activity]
    if not all(math.isfinite(x) for x in numeric) or not all(.25 <= x <= 16 for x in args.speeds) or not .9 <= args.min_ratio <= 1 or not 1 <= args.min_fps <= args.fps or args.p99_ms <= 0 or not 0 <= args.min_activity <= 1:
        parser.error("finite valid rates/criteria required")
    Search(args).run()
    print(args.out.resolve() / "report.md", flush=True)
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
