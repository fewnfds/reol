#!/usr/bin/env python3
"""Launch an isolated, temporary crowd demo using the real world and NPC owners."""
from __future__ import annotations

import argparse
import subprocess
import time

import godot


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--residents", type=int, default=50, help="per settlement; 6..256, total bodies = twice this value")
    parser.add_argument("--seconds", type=int, default=30, help="bounded capture 5..300 seconds after loading")
    parser.add_argument("--quit-after-capture", action="store_true", help="otherwise keep playing the temporary world")
    parser.add_argument("--headless", action="store_true", help="rules/CPU diagnostics only, not rendering performance")
    parser.add_argument("--opening-wave", action="store_true", help="single ordinary rest journey, for the original before/after comparison")
    parser.add_argument("--profile-kernel", action="store_true", help="wrap every world phase for diagnosis; adds overhead, disabled for throughput captures")
    parser.add_argument("--actor-workers", type=int, choices=range(9), default=4, help="native actor calculation workers; 0 uses the same packed calculation serially")
    args = parser.parse_args()
    if not 6 <= args.residents <= 256 or not 5 <= args.seconds <= 300:
        parser.error("residents must be 6..256 and seconds 5..300")
    executable = godot.find_godot()
    if executable is None:
        parser.error("Godot was not found; run python tools/godot.py doctor")
    sha = subprocess.check_output(["git", "rev-parse", "HEAD"], cwd=godot.ROOT, text=True).strip()
    tag = f"crowd-{args.residents * 2}-{time.strftime('%Y%m%d-%H%M%S')}"
    print(f"Temporary crowd: {args.residents * 2} bodies; report logs/{tag}.json", flush=True)
    cmd = [str(executable), "--path", str(godot.ROOT)]
    if args.headless:
        cmd.append("--headless")
    cmd += ["--script", "res://tools/qa/crowd_stress_demo.gd", "--", f"--residents={args.residents}",
            f"--seconds={args.seconds}", f"--report=res://logs/{tag}.json", f"--revision={sha}",
            f"--actor-workers={args.actor_workers}"]
    if args.quit_after_capture:
        cmd.append("--quit-after-capture")
    if args.opening_wave:
        cmd.append("--opening-wave")
    if args.profile_kernel:
        cmd.append("--profile-kernel")
    return godot._run(cmd, tag, timeout=args.seconds + 180 if args.quit_after_capture else None)


if __name__ == "__main__":
    raise SystemExit(main())
