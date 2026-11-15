"""A few seconds to check process exits and watchdogs; no test framework."""

from contextlib import redirect_stderr, redirect_stdout
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
import benchmark
import check_structure


def check_short_suites() -> None:
    """Topic selection must reach Godot without bypassing the same watchdog."""
    for suite in ("kernel", "features", "sight", "equipment"):
        args = godot.build_parser().parse_args(["test", "--suite", suite])
        with patch.object(godot, "_require_godot", return_value=Path("godot.exe")), patch.object(godot, "_run", return_value=7) as run:
            assert godot.cmd_test(args) == 7
            assert run.call_args.args[0][-2:] == ["--", f"--suite={suite}"]
            assert run.call_args.kwargs["timeout"] == 15
    with redirect_stderr(io.StringIO()):
        try:
            godot.build_parser().parse_args(["test", "--suite", "unknown"])
        except SystemExit as error:
            assert error.code == 2
        else:
            raise AssertionError("Unknown suite silently skipped checks")


def check_resource_and_document_paths(directory: Path) -> None:
    """A native Resource edge is live code; a missing section is a broken link."""
    root = directory / "structure"
    for folder in ("scripts", "scenes", "data/definitions"):
        (root / folder).mkdir(parents=True, exist_ok=True)
    (root / "project.godot").write_text('run/main_scene="res://scenes/main.tscn"\n', encoding="utf-8")
    (root / "scenes/main.tscn").write_text('[ext_resource path="res://data/definitions/pool.tres"]\n', encoding="utf-8")
    (root / "data/definitions/pool.tres").write_text('[ext_resource path="res://scripts/pool.gd"]\n', encoding="utf-8")
    (root / "scripts/pool.gd").write_text("extends Resource\n", encoding="utf-8")
    (root / "scripts/pool.gd.uid").write_text("uid://example\n", encoding="utf-8")
    assert not any("no static entry path" in note for note in check_structure.audit_code(root))
    target = root / "target.md"
    target.write_text("# 当前能力\n## 状态、属性与资源\n## 当前能力\n", encoding="utf-8")
    entry = root / "entry.md"
    entry.write_text("[valid](target.md#状态属性与资源)\n[duplicate](target.md#当前能力-1)\n[broken](target.md#已删除的进度)\n[optional local](.local/advisor/README.md)\n", encoding="utf-8")
    issues = check_structure.check_markdown(entry, root)
    assert len(issues) == 1 and "已删除的进度" in issues[0]
    (root / "scripts/pool.gd").write_text('const Bad = preload("res://scripts/deleted.gd")\n', encoding="utf-8")
    assert check_structure.check_script(root / "scripts/pool.gd", root)


def check_response_capture(directory: Path) -> None:
    """Response samples must be explicit and cannot masquerade as capacity-v1."""
    binary = directory / "response-demo.exe"
    binary.write_bytes(b"engine")
    argv = ["benchmark.py", "--binary", str(binary), "--actors", "24", "--speed", "1", "--response-probe"]
    with patch.object(sys, "argv", argv), patch.object(benchmark, "capture", return_value={"capture_exit_code": 0}) as capture:
        assert benchmark.main() == 0
        assert capture.call_args.kwargs["response_probe"] is True
        assert capture.call_args.kwargs["sim_hz"] == 60
    with patch.object(sys, "argv", argv[:-1] + ["--sim-hz", "100", "--combat-lab"]), patch.object(benchmark, "capture", return_value={"capture_exit_code": 0}) as capture:
        assert benchmark.main() == 0
        assert capture.call_args.kwargs["sim_hz"] == 100 and capture.call_args.kwargs["combat_lab"]
    for incompatible in [["--mixed"], ["--capacity"], ["--combat-lab"], ["--speed", "2"]]:
        with patch.object(sys, "argv", argv + incompatible), redirect_stderr(io.StringIO()):
            try:
                benchmark.main()
            except SystemExit as error:
                assert error.code == 2
            else:
                raise AssertionError("Response probe accepted an incompatible historical fixture")


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
    for case in ["normal", "overload", "cost", "different_window", "different_combat", "different_hz", "invalid"]:
        calls = []

        def capture(**kw):
            calls.append((kw["speed"], kw["actors"]))
            actual = kw["speed"] * (.6 if case == "overload" else 1)
            return {"capture_exit_code": int(case == "invalid"), "release": True, "scenario": "capacity-act-v1" if case == "different_combat" else "capacity-v1", "sim_hz": 60 if case in ["different_combat", "different_hz"] else 20,
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
                    "different_window": "not_comparable", "different_combat": "not_comparable", "different_hz": "not_comparable", "invalid": "invalid"}[case]
        for sample, result in zip(samples, check.result["results"]):
            per_speed = [count for speed, count in calls if speed == sample["speed"]]
            assert per_speed[0] == sample["actors"] and len(per_speed) <= 3
            assert result["verdict"] == expected
            if case in ["normal", "different_window", "different_combat", "different_hz", "invalid"]:
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
                check_response_capture(Path(directory))
                check_short_suites()
                check_resource_and_document_paths(Path(directory))
        finally:
            godot.LOG_DIR = original
    print(f"Tool smoke passed in {time.monotonic() - started:.3f}s")


if __name__ == "__main__":
    main()
