#!/usr/bin/env python3
"""Launch an isolated, temporary crowd demo using the real world and NPC owners."""
from __future__ import annotations

import argparse
import hashlib
import json
import subprocess
import time
from pathlib import Path

import godot
from cpu_sample import ProcessSample


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--residents", type=int, default=50, help="per settlement; 6..4096, total bodies = twice this value")
    parser.add_argument("--seconds", type=int, default=30, help="bounded capture 5..300 seconds after loading")
    parser.add_argument("--quit-after-capture", action="store_true", help="otherwise keep playing the temporary world")
    parser.add_argument("--headless", action="store_true", help="rules/CPU diagnostics only, not rendering performance")
    parser.add_argument("--opening-wave", action="store_true", help="single ordinary rest journey, for the original before/after comparison")
    parser.add_argument("--mixed", action="store_true", help="exercise stock delivery, a real recipe, a door, moving view and limited combat")
    parser.add_argument("--complex", action="store_true", help="dense local crowd, real enclosed rooms and alternating physical heat/cold/five-element sources")
    parser.add_argument("--rooms", type=int, default=48, help="complex scenario rooms, 1..64")
    parser.add_argument("--sources", type=int, default=128, help="complex scenario physical field sources, 5..512")
    parser.add_argument("--profile-kernel", action="store_true", help="wrap every world phase for diagnosis; adds overhead, disabled for throughput captures")
    parser.add_argument("--profile-render", action="store_true", help="enable Godot viewport CPU/GPU rendering timings; adds measurement overhead")
    parser.add_argument("--profile-navigation", action="store_true", help="time native/service path providers and retain at most 4096 query coordinates for parallel replay")
    parser.add_argument("--profile-cpu", action="store_true", help="sample owned Windows process per-thread CPU execution and memory every 0.5s")
    parser.add_argument("--gpu-index", type=int, help="pin a Godot rendering adapter index; verify the report renderer name")
    parser.add_argument("--input-probe", action="store_true", help="measure a harmless host request's wait for the same complete-world boundary as gameplay input")
    parser.add_argument("--pacing-policy", choices=("auto", "full-rate"), default="auto", help="diagnostic full-rate bypasses adaptive slowdown, preserving bounded debt and the normal cooperative work budget")
    parser.add_argument("--actor-workers", type=int, choices=range(-1, 65), default=4, help="shared batch worker cap; -1 adapts to hardware/chunks, 0 is same-algorithm serial, 1..64 explicit experiment")
    parser.add_argument("--actor-projection", choices=("partitioned", "ordered"), default="partitioned", help="compare proven disjoint body adoption with original ID-by-ID projection; notifications remain ordered")
    parser.add_argument("--actor-minimum", type=int, choices=range(1, 4097), default=64, help="smallest body candidate batch; smaller sets retain the direct owner path")
    parser.add_argument("--simulation-thread", choices=("on", "off"), default="on", help="same world runner on its coordinator thread or synchronously for a same-build comparison")
    parser.add_argument("--environment-backend", choices=("auto", "cpu", "gpu"), default="auto", help="compare ordinary source candidate calculation; auto keeps small batches on CPU")
    parser.add_argument("--release", action="store_true", help="export the current project with Windows Performance, then run the identical crowd entry in its release binary")
    parser.add_argument("--release-binary", type=Path, help="reuse a specific exported binary for same-build worker/scale comparisons; requires --release")
    args = parser.parse_args()
    if not 6 <= args.residents <= 4096 or not 5 <= args.seconds <= 300:
        parser.error("residents must be 6..4096 and seconds 5..300")
    if args.mixed and (args.opening_wave or args.residents < 14 or args.seconds < 45):
        parser.error("mixed requires at least 14 residents per settlement and 45 seconds, without --opening-wave")
    if args.complex and (args.mixed or args.opening_wave or not 1 <= args.rooms <= 64 or not 5 <= args.sources <= 512):
        parser.error("complex requires rooms 1..64 and sources 5..512, without mixed/opening-wave")
    if args.release_binary and (not args.release or not args.release_binary.is_file()):
        parser.error("release-binary requires --release and an existing executable")
    executable = godot.find_godot()
    if executable is None:
        parser.error("Godot was not found; run python tools/godot.py doctor")
    sha = subprocess.check_output(["git", "rev-parse", "HEAD"], cwd=godot.ROOT, text=True).strip()
    dirty = bool(subprocess.check_output(["git", "status", "--porcelain"], cwd=godot.ROOT, text=True).strip())
    tag = f"crowd-{'release-' if args.release else ''}{'complex-' if args.complex else 'mixed-' if args.mixed else ''}{args.residents * 2}-{time.strftime('%Y%m%d-%H%M%S')}"
    print(f"Temporary crowd: {args.residents * 2} bodies; report logs/{tag}.json", flush=True)
    if args.release:
        output = args.release_binary.resolve() if args.release_binary else godot.ROOT / "logs" / "release-stress" / tag / "reol-perf.exe"
        output.parent.mkdir(parents=True, exist_ok=True)
        if not args.release_binary:
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
        provenance = output.with_suffix(".build.json")
        if args.release_binary:
            # Launching an old artifact after editing/committing the checkout
            # must not relabel it as a build of the current source revision.
            build = json.loads(provenance.read_text(encoding="utf-8")) if provenance.is_file() else {}
            if build.get("artifact_sha256") != artifact_sha:
                sha, dirty = "unknown", True
            else:
                sha, dirty = build["revision"], build["dirty"]
        else:
            provenance.write_text(json.dumps({"revision": sha, "dirty": dirty,
                                  "artifact_sha256": artifact_sha}, indent=2), encoding="utf-8")
        cmd = [str(output)]
    else:
        cmd = [str(executable), "--path", str(godot.ROOT), "res://scenes/diagnostics/crowd_stress.tscn"]
    if args.headless:
        cmd.append("--headless")
    if args.gpu_index is not None:
        cmd += ["--gpu-index", str(args.gpu_index)]
    report = (godot.ROOT / "logs" / f"{tag}.json").as_posix()
    cmd += ["--", f"--residents={args.residents}",
            f"--seconds={args.seconds}", f"--report={report}", f"--revision={sha}", f"--source-dirty={int(dirty)}",
            f"--actor-workers={args.actor_workers}", f"--actor-projection={args.actor_projection}", f"--actor-minimum={args.actor_minimum}", f"--simulation-thread={args.simulation_thread}", f"--environment-backend={args.environment_backend}",
            f"--pacing-policy={args.pacing_policy}"]
    if args.release:
        cmd.append(f"--artifact-sha256={artifact_sha}")
    if args.quit_after_capture:
        cmd.append("--quit-after-capture")
    if args.opening_wave:
        cmd.append("--opening-wave")
    if args.mixed:
        cmd.append("--mixed")
    if args.complex:
        cmd += ["--complex", f"--rooms={args.rooms}", f"--sources={args.sources}"]
    if args.profile_kernel:
        cmd.append("--profile-kernel")
    if args.profile_render:
        cmd.append("--profile-render")
    if args.profile_navigation:
        cmd.append("--profile-navigation")
    if args.input_probe:
        cmd.append("--input-probe")
    sampler = ProcessSample(godot.ROOT / "logs" / f"{tag}.cpu.json") if args.profile_cpu else None
    try:
        return godot._run(cmd, tag, timeout=args.seconds + 90 if args.quit_after_capture else None,
                         on_start=sampler.start if sampler else None)
    finally:
        if sampler:
            sampler.close()


if __name__ == "__main__":
    raise SystemExit(main())
