"""A few seconds to check process exits and watchdogs; no test framework."""

from contextlib import redirect_stdout
from argparse import Namespace
import io
import json
from pathlib import Path
import sys
import tempfile
import time
from unittest.mock import patch

sys.path.insert(0, str(Path(__file__).resolve().parents[1] / "tools"))
import godot
import capacity


def check_performance_budget(directory: Path) -> None:
    """History is reused, capture counts are bounded, and unlike loads aren't compared."""
    binary = directory / "demo.exe"
    binary.write_bytes(b"engine")
    binary.with_suffix(".pck").write_bytes(b"game")
    host = {"cpu": "test CPU", "logical_cpus": 20, "renderer": "test GPU"}
    config = {"fps": 60, "workers": -1, "fog": False, "camera": {"zoom": .209999993443489, "position": [7040, 7040]}}
    speeds = [1, 2, 4, 8, 16]
    samples = [{"speed": speed, "actors": count, "seconds": 10, "actual_speed": speed,
                "step_mean_ms": 10, "process_mean_ms": 2, "gpu_mean_ms": 1,
                "frame_mean_ms": 16.67, "frame_p99_ms": 20}
               for speed, count in zip(speeds, [4600, 2000, 900, 400, 200])]
    baseline = directory / "reference.json"
    baseline.write_text(json.dumps({"format": "reol-performance-baseline-v1", "scenario": "capacity-v1",
                                   "hardware": host, "config": config, "samples": samples}), encoding="utf-8")
    original = baseline.read_bytes()
    for case in ["normal", "overload", "cost", "different_window", "invalid"]:
        calls = []

        def capture(**kw):
            calls.append((kw["speed"], kw["actors"]))
            actual = kw["speed"] * (.6 if case == "overload" else 1)
            return {"capture_exit_code": int(case == "invalid"), "release": True, "scenario": "capacity-v1",
                    "fog": False, "camera": config["camera"], "renderer": host["renderer"],
                    "actors": kw["actors"], "alive": kw["actors"], "requested_speed": kw["speed"],
                    "actual_speed": actual, "wall_seconds": kw["seconds"], "world_delta_ms": 1000,
                    "moved_cells_delta": 50, "material": 100, "initial_material": 100,
                    "activity_fraction": {"mean": .8}, "overload_demand_usec_delta": 0,
                    "segments": [{"actual_speed": actual}] * 2,
                    "step_mean_ms": 12 if case == "cost" else 10,
                    "frame_ms": {"mean": 16.67, "p99": 20}, "process_ms": {"mean": 2}, "gpu_ms": {"mean": 1}}

        args = Namespace(binary=binary, baseline=baseline, out=directory / case, speeds=speeds, max_trials=3,
                         seconds=5 if case == "different_window" else None, fps=60, workers=-1, gpu_index=1,
                         min_ratio=.98, min_fps=57, p99_ms=33.34, min_activity=.5, regression_pct=15)
        with patch.object(capacity, "hardware", return_value=host.copy()), patch.object(capacity.benchmark, "capture", side_effect=capture):
            check = capacity.Check(args)
            check.run()
        expected = {"normal": "acceptable", "overload": "capacity_regressed", "cost": "review_cost",
                    "different_window": "not_comparable", "invalid": "invalid"}[case]
        for sample, result in zip(samples, check.result["results"]):
            per_speed = [count for speed, count in calls if speed == sample["speed"]]
            assert per_speed[0] == sample["actors"] and len(per_speed) <= 3
            assert result["verdict"] == expected
            if case in ["normal", "different_window", "invalid"]:
                assert len(per_speed) == 1
        assert baseline.read_bytes() == original  # Never silently rebase a regression.
        if case not in ["invalid", "overload"]:
            assert capacity.load_reference(args.out / "summary.json")


def main() -> None:
    started = time.monotonic()
    with tempfile.TemporaryDirectory() as directory:
        original = godot.LOG_DIR
        godot.LOG_DIR = Path(directory)
        try:
            with redirect_stdout(io.StringIO()):
                assert godot._run([sys.executable, "-c", "print('ok')"], "clean", timeout=2) == 0
                assert godot._run([sys.executable, "-c", "import sys; sys.exit(7)"], "exit", timeout=2) == 7
                error = "import time; print('SCRIPT ERROR: deliberate smoke',flush=True); time.sleep(10)"
                assert godot._run([sys.executable, "-u", "-c", error], "error", timeout=2) == 1
                assert godot._run([sys.executable, "-c", "import time; time.sleep(10)"], "timeout", timeout=.2) == 124
                assert "timed out" in next(Path(directory).glob("timeout-*.log")).read_text()
                check_performance_budget(Path(directory))
        finally:
            godot.LOG_DIR = original
    print(f"Tool smoke passed in {time.monotonic() - started:.3f}s")


if __name__ == "__main__":
    main()
