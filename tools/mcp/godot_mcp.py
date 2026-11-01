#!/usr/bin/env python3
"""stdio wrapper for @coding-solo/godot-mcp.

Resolves the Godot executable via tools/godot.py and exports GODOT_PATH so the
MCP server can find it. stdout is reserved for the MCP protocol; diagnostics go
to stderr.
"""

from __future__ import annotations

import os
import shutil
import subprocess
import sys
from pathlib import Path

ROOT = Path(__file__).resolve().parents[2]
sys.path.insert(0, str(ROOT / "tools"))

from godot import find_godot  # noqa: E402

PACKAGE = "@coding-solo/godot-mcp@0.1.1"


def main() -> int:
    os.chdir(ROOT)

    godot = find_godot()
    if godot is not None:
        os.environ.setdefault("GODOT_PATH", str(godot))
        print(f"[godot-mcp] GODOT_PATH={godot}", file=sys.stderr)
    else:
        print(
            "[godot-mcp] Godot not found. Set GODOT_BIN; tools that need the engine will fail.",
            file=sys.stderr,
        )

    npx = shutil.which("npx") or shutil.which("npx.cmd")
    if npx is None:
        print("[godot-mcp] npx not found. Install Node.js 18+.", file=sys.stderr)
        return 127

    if os.name == "nt":
        cmd = ["cmd", "/c", npx, "-y", PACKAGE]
    else:
        cmd = [npx, "-y", PACKAGE]

    try:
        return subprocess.call(cmd, cwd=ROOT)
    except OSError as exc:
        print(f"[godot-mcp] failed to start npx: {exc}", file=sys.stderr)
        return 127


if __name__ == "__main__":
    raise SystemExit(main())
