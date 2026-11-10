#!/usr/bin/env python3
"""Launch the ordinary demo with an isolated, bounded performance recorder."""
from __future__ import annotations

import argparse
import os
import subprocess
import time

import godot


def capture_seconds(value: str) -> int:
    seconds = int(value)
    if not 1 <= seconds <= 300:
        raise argparse.ArgumentTypeError("capture must last 1 to 300 seconds")
    return seconds


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--seconds", type=capture_seconds, default=120)
    parser.add_argument("--headless", action="store_true", help="tool smoke only; cannot measure rendering")
    parser.add_argument("--auto-start", action="store_true", help="choose the ordinary human opening for unattended QA")
    parser.add_argument("--profile-kernel", action="store_true", help="add detailed world-phase timings; has additional measurement overhead")
    parser.add_argument("--quit-after-capture", action="store_true", help="close this new demo after capture (default: keep playing)")
    args = parser.parse_args()
    executable = godot.find_godot()
    if executable is None:
        parser.error("Godot was not found; run python tools/godot.py doctor")
    revision = subprocess.run(["git", "rev-parse", "HEAD"], cwd=godot.ROOT, capture_output=True, text=True)
    sha = revision.stdout.strip() if revision.returncode == 0 else "unknown"
    status = subprocess.run(["git", "status", "--porcelain"], cwd=godot.ROOT, capture_output=True, text=True)
    dirty = status.returncode != 0 or bool(status.stdout.strip())
    tag = f"demo-profile-{time.strftime('%Y%m%d-%H%M%S')}-{os.getpid()}"
    output = godot.ROOT / "logs" / f"{tag}.json"
    cmd = [str(executable), "--path", str(godot.ROOT)]
    if args.headless:
        cmd.append("--headless")
    cmd += ["--script", "res://tools/qa/demo_diagnostics.gd", "--",
            f"--capture-seconds={args.seconds}", f"--report=res://logs/{tag}.json",
            f"--revision={sha}", f"--dirty={str(dirty).lower()}"]
    if args.auto_start:
        cmd.append("--auto-start")
    if args.quit_after_capture:
        cmd.append("--quit-after-capture")
    if args.profile_kernel:
        cmd.append("--profile-kernel")
    print(f"Performance report: {output}", flush=True)
    print("Capture stops automatically; the demo stays open unless --quit-after-capture is supplied.", flush=True)
    return godot._run(cmd, tag, timeout=args.seconds + 90 if args.quit_after_capture else None)


if __name__ == "__main__":
    raise SystemExit(main())
