#!/usr/bin/env python3
"""Bounded release capture of the current kernel; no historical CI matrix."""
from __future__ import annotations

import argparse
import hashlib
import json
from pathlib import Path
import subprocess
import time

import godot
from cpu_sample import ProcessSample


def capture(*, binary: Path, actors: int, speed: float, fps: int, workers: int,
            seconds: int, gpu_index: int, output: Path, fog: bool = False,
            mixed: bool = False, capacity: bool = False, screenshot: bool = False) -> dict:
    """One owned real-window process, bounded lifetime, no concurrent GPU runs."""
    binary, output = binary.resolve(), output.resolve()
    if output.exists():
        raise FileExistsError(f"Refusing stale capture/overwrite: {output}")
    output.parent.mkdir(parents=True, exist_ok=True)
    command = [str(binary), "--gpu-index", str(gpu_index), "--resolution", "1280x720", "--",
               f"--actors={actors}", f"--speed={speed}", f"--fps={fps}",
               f"--workers={workers}", f"--duration={seconds}", "--warmup=3", f"--metrics={output}"]
    if screenshot:
        command.append(f"--screenshot={output.with_suffix('.png')}")
    if mixed:
        command.append("--mixed=true")
    if capacity:
        command.append("--capacity=true")
    # A false flag must be explicit too: Game's ordinary-start default varies
    # at 1000 actors. Capacity comparisons must not inherit that transition.
    command.append("--fog=true" if fog else "--fog=false")
    with output.with_suffix(".log").open("w", encoding="utf-8") as log:
        process = subprocess.Popen(command, cwd=godot.ROOT, stdout=log, stderr=subprocess.STDOUT)
        sampler = ProcessSample(output.with_suffix(".cpu.json"))
        sampler.start(process.pid)
        try:
            code = process.wait(timeout=seconds + 25)
        except subprocess.TimeoutExpired:
            process.kill()
            process.wait()
            code = 124
        finally:
            if process.poll() is None:
                process.kill()
                process.wait()
            sampler.close()
    if not output.is_file():
        return {"capture_exit_code": code or 1, "capture_error": "missing_metrics", "log": str(output.with_suffix('.log'))}
    result = json.loads(output.read_text(encoding="utf-8"))
    errors = [line for line in output.with_suffix(".log").read_text(encoding="utf-8", errors="replace").splitlines()
              if line.strip().startswith(("SCRIPT ERROR:", "ERROR:"))]
    result["capture_exit_code"] = code or int(bool(errors))
    result["capture_errors"] = errors[:8]
    result["cpu_sample_file"] = str(output.with_suffix(".cpu.json"))
    result["binary_sha256"] = hashlib.sha256(binary.read_bytes()).hexdigest()
    pack = binary.with_suffix(".pck")
    if pack.is_file():
        result["pack_sha256"] = hashlib.sha256(pack.read_bytes()).hexdigest()
    result["git_commit"] = subprocess.check_output(["git", "rev-parse", "HEAD"], cwd=godot.ROOT, text=True).strip()
    result["git_dirty"] = bool(subprocess.check_output(["git", "status", "--porcelain"], cwd=godot.ROOT, text=True).strip())
    result["headless"] = False
    output.write_text(json.dumps(result, ensure_ascii=False, indent=2), encoding="utf-8")
    return result


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--binary", type=Path, default=godot.ROOT / "build/windows/reol-demo.exe")
    parser.add_argument("--actors", type=int, default=1000)
    parser.add_argument("--speed", type=float, default=4)
    parser.add_argument("--fps", type=int, default=60)
    parser.add_argument("--workers", type=int, default=-1)
    parser.add_argument("--seconds", type=int, default=20)
    parser.add_argument("--gpu-index", type=int, default=1)
    parser.add_argument("--out", type=Path)
    parser.add_argument("--screenshot", action="store_true")
    parser.add_argument("--fog", action="store_true", help="player fog view instead of full developer overview")
    parser.add_argument("--mixed", action="store_true", help="100 fighters, 20 material builds and contact exchanges")
    parser.add_argument("--capacity", action="store_true", help="durable mixed capacity-v1 starting fixture")
    args = parser.parse_args()
    if not args.binary.is_file() or not 5 <= args.seconds <= 60 or not 1 <= args.actors <= 60000 or not .25 <= args.speed <= 16 or not 10 <= args.fps <= 240 or not -1 <= args.workers <= 64:
        parser.error("existing release binary; 1..60000 actors; .25..16 speed; 5..60 seconds; 10..240 FPS; -1..64 workers")
    output = (args.out or godot.ROOT / "logs" / f"kernel-{args.actors}-{args.speed:g}x-{args.fps}-{time.strftime('%Y%m%d-%H%M%S')}.json").resolve()
    result = capture(binary=args.binary, actors=args.actors, speed=args.speed, fps=args.fps,
                     workers=args.workers, seconds=args.seconds, gpu_index=args.gpu_index,
                     output=output, fog=args.fog, mixed=args.mixed, capacity=args.capacity, screenshot=args.screenshot)
    print(json.dumps({key: result.get(key) for key in ["actors", "workers", "requested_speed", "actual_speed", "fps_limit", "frame_ms", "step_ms", "deliveries_delta", "material", "overload_demand_usec_delta"]}, ensure_ascii=False), flush=True)
    print(output, flush=True)
    return int(result["capture_exit_code"])


if __name__ == "__main__":
    raise SystemExit(main())
