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
    parser.add_argument("--fog", action="store_true", help="render the player fog view instead of the full developer overview")
    parser.add_argument("--mixed", action="store_true", help="100 sustained fighters, 20 material builds and contact exchanges")
    args = parser.parse_args()
    binary = args.binary.resolve()
    if not binary.is_file() or not 5 <= args.seconds <= 60 or not 1 <= args.actors <= 60000:
        parser.error("use an existing release binary, 1..60000 actors and 5..60 seconds")
    output = (args.out or godot.ROOT / "logs" / f"kernel-{args.actors}-{args.speed:g}x-{args.fps}-{time.strftime('%Y%m%d-%H%M%S')}.json").resolve()
    output.parent.mkdir(parents=True, exist_ok=True)
    command = [str(binary), "--gpu-index", str(args.gpu_index), "--resolution", "1280x720", "--",
               f"--actors={args.actors}", f"--speed={args.speed}", f"--fps={args.fps}",
               f"--workers={args.workers}", f"--duration={args.seconds}", "--warmup=3", f"--metrics={output}"]
    if args.screenshot:
        command.append(f"--screenshot={output.with_suffix('.png')}")
    if args.mixed:
        command.append("--mixed=true")
    if args.fog:
        command.append("--fog=true")
    with output.with_suffix(".log").open("w", encoding="utf-8") as log:
        process = subprocess.Popen(command, cwd=godot.ROOT, stdout=log, stderr=subprocess.STDOUT)
        sampler = ProcessSample(output.with_suffix(".cpu.json"))
        sampler.start(process.pid)
        try:
            code = process.wait(timeout=args.seconds + 25)
        except subprocess.TimeoutExpired:
            process.kill()
            process.wait()
            code = 124
        finally:
            sampler.close()
    if not output.is_file():
        print(f"Capture failed ({code}); inspect {output.with_suffix('.log')}", flush=True)
        return code or 1
    result = json.loads(output.read_text(encoding="utf-8"))
    result["cpu_sample_file"] = str(output.with_suffix(".cpu.json"))
    result["binary_sha256"] = hashlib.sha256(binary.read_bytes()).hexdigest()
    pack = binary.with_suffix(".pck")
    if pack.is_file():
        result["pack_sha256"] = hashlib.sha256(pack.read_bytes()).hexdigest()
    result["git_commit"] = subprocess.check_output(["git", "rev-parse", "HEAD"], cwd=godot.ROOT, text=True).strip()
    result["git_dirty"] = bool(subprocess.check_output(["git", "status", "--porcelain"], cwd=godot.ROOT, text=True).strip())
    result["headless"] = False
    output.write_text(json.dumps(result, ensure_ascii=False, indent=2), encoding="utf-8")
    print(json.dumps({key: result.get(key) for key in ["actors", "workers", "requested_speed", "actual_speed", "fps_limit", "frame_ms", "step_ms", "deliveries_delta", "material", "overload_demand_usec_delta"]}, ensure_ascii=False), flush=True)
    print(output, flush=True)
    return code


if __name__ == "__main__":
    raise SystemExit(main())
