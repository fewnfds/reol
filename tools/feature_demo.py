#!/usr/bin/env python3
"""Launch the small playable feature tour, separate from the crowd benchmark."""
from __future__ import annotations

import argparse

import godot


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--gpu-index", type=int, help="choose a Godot rendering adapter")
    args = parser.parse_args()
    binary = godot.find_godot()
    if binary is None:
        parser.error("Godot was not found; set GODOT_BIN or run tools/godot.py doctor")
    command = [str(binary), "--path", str(godot.ROOT)]
    if args.gpu_index is not None:
        command += ["--gpu-index", str(args.gpu_index)]
    command.append("res://scenes/demos/feature_tour.tscn")
    return godot._run(command, "feature-tour", fail_fast=False)


if __name__ == "__main__":
    raise SystemExit(main())
