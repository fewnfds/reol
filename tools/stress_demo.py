#!/usr/bin/env python3
"""Launch an isolated, temporary crowd demo using the real world and NPC owners."""
from __future__ import annotations

import argparse
import hashlib
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
    parser.add_argument("--profile-render", action="store_true", help="enable Godot viewport CPU/GPU rendering timings; adds measurement overhead")
    parser.add_argument("--actor-workers", type=int, choices=range(9), default=4, help="native actor calculation workers; 0 uses the same packed calculation serially")
    parser.add_argument("--environment-backend", choices=("auto", "cpu", "gpu"), default="auto", help="compare ordinary source candidate calculation; auto keeps small batches on CPU")
    parser.add_argument("--release", action="store_true", help="export the current project with Windows Performance, then run the identical crowd entry in its release binary")
    args = parser.parse_args()
    if not 6 <= args.residents <= 256 or not 5 <= args.seconds <= 300:
        parser.error("residents must be 6..256 and seconds 5..300")
    executable = godot.find_godot()
    if executable is None:
        parser.error("Godot was not found; run python tools/godot.py doctor")
    sha = subprocess.check_output(["git", "rev-parse", "HEAD"], cwd=godot.ROOT, text=True).strip()
    dirty = bool(subprocess.check_output(["git", "status", "--porcelain"], cwd=godot.ROOT, text=True).strip())
    tag = f"crowd-{'release-' if args.release else ''}{args.residents * 2}-{time.strftime('%Y%m%d-%H%M%S')}"
    print(f"Temporary crowd: {args.residents * 2} bodies; report logs/{tag}.json", flush=True)
    if args.release:
        output = godot.ROOT / "logs" / "release-stress" / "reol-perf.exe"
        output.parent.mkdir(parents=True, exist_ok=True)
        result = godot._run([str(executable), "--headless", "--quiet", "--path", str(godot.ROOT),
                             "--export-release", "Windows Performance", str(output)], "performance-release-export", timeout=45)
        if result:
            return result
        digest = hashlib.sha256()
        for artifact in (output, output.with_suffix(".pck")):
            with artifact.open("rb") as stream:
                for chunk in iter(lambda: stream.read(1024 * 1024), b""):
                    digest.update(chunk)
        artifact_sha = digest.hexdigest()
        cmd = [str(output)]
    else:
        cmd = [str(executable), "--path", str(godot.ROOT), "--script", "res://tools/qa/crowd_stress_demo.gd"]
    if args.headless:
        cmd.append("--headless")
    report = (godot.ROOT / "logs" / f"{tag}.json").as_posix()
    cmd += ["--", f"--residents={args.residents}",
            f"--seconds={args.seconds}", f"--report={report}", f"--revision={sha}", f"--source-dirty={int(dirty)}",
            f"--actor-workers={args.actor_workers}", f"--environment-backend={args.environment_backend}"]
    if args.release:
        cmd.append(f"--artifact-sha256={artifact_sha}")
    if args.quit_after_capture:
        cmd.append("--quit-after-capture")
    if args.opening_wave:
        cmd.append("--opening-wave")
    if args.profile_kernel:
        cmd.append("--profile-kernel")
    if args.profile_render:
        cmd.append("--profile-render")
    return godot._run(cmd, tag, timeout=args.seconds + 45 if args.quit_after_capture else None)


if __name__ == "__main__":
    raise SystemExit(main())
