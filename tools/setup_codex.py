#!/usr/bin/env python3
"""Create local Codex MCP entries using this checkout's absolute paths.

No packages are installed. Existing Codex settings and server entries are kept.
Godot AI configures its own authenticated bridge from the editor dock.
"""

from __future__ import annotations

import argparse
import json
import shutil
import sys
import time
import tomllib
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
CONFIG = ROOT / ".codex" / "config.toml"


def expected_servers() -> dict[str, dict]:
    return {
        "godot": {
            "command": sys.executable,
            "args": [str(ROOT / "tools" / "mcp" / "godot_mcp.py")],
            "cwd": str(ROOT),
            "startup_timeout_sec": 65,
            "tool_timeout_sec": 65,
            "enabled": True,
        },
        "context7": {
            "url": "https://mcp.context7.com/mcp",
            "startup_timeout_sec": 30,
            "tool_timeout_sec": 60,
            "enabled": True,
        },
    }


def render_server(name: str, settings: dict) -> str:
    # JSON strings, booleans, and string arrays are also valid TOML values.
    lines = [f"[mcp_servers.{name}]"]
    lines.extend(f"{key} = {json.dumps(value)}" for key, value in settings.items())
    return "\n".join(lines) + "\n"


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--check", action="store_true", help="Validate without writing")
    args = parser.parse_args()

    skills = sorted((ROOT / ".agents" / "skills").glob("*/SKILL.md"))
    if not skills:
        print("ERROR: No project skills found in .agents/skills", file=sys.stderr)
        return 1
    print(f"Project skills: {len(skills)} ({ROOT / '.agents' / 'skills'})")

    try:
        original = CONFIG.read_text(encoding="utf-8") if CONFIG.exists() else ""
        data = tomllib.loads(original)
    except (OSError, tomllib.TOMLDecodeError) as exc:
        print(f"ERROR: Cannot read {CONFIG}: {exc}", file=sys.stderr)
        return 1

    existing = data.get("mcp_servers", {})
    additions: list[str] = []
    problems: list[str] = []
    for name, expected in expected_servers().items():
        if name not in existing:
            additions.append(render_server(name, expected))
            print(f"{'MISSING' if args.check else 'ADD'} MCP: {name}")
            continue
        current = existing[name]
        # Respect user-owned timeouts, env, and tool selection. Never replace a
        # server with another command or silently re-enable a disabled server.
        for key in ("command", "args", "cwd", "url"):
            if key in expected and current.get(key) != expected[key]:
                problems.append(f"{name}: {key} differs from this checkout")
        if current.get("enabled", True) is False:
            problems.append(f"{name}: disabled in local project config")
        print(f"PRESENT MCP: {name}")

    if problems:
        for problem in problems:
            print(f"ERROR: {problem}; existing entry preserved", file=sys.stderr)
        return 1
    if args.check and additions:
        print("Run: python tools/setup_codex.py")
        return 1
    if additions:
        CONFIG.parent.mkdir(parents=True, exist_ok=True)
        if CONFIG.exists():
            stamp = time.strftime("%Y%m%d-%H%M%S")
            backup = CONFIG.with_name(f"config.toml.{stamp}-{time.time_ns()}.bak")
            shutil.copy2(CONFIG, backup)
            print(f"Backup: {backup}")
        updated = original.rstrip() + "\n\n" + "\n".join(additions)
        tomllib.loads(updated)
        temporary = CONFIG.with_suffix(".toml.tmp")
        temporary.write_text(updated.lstrip(), encoding="utf-8")
        temporary.replace(CONFIG)
        print(f"Wrote: {CONFIG}")
    print("Codex project config OK (takes effect when Codex reloads the project).")
    print("Godot AI: use Godot AI dock -> Configure -> Codex; no manual ports.")
    return 0


if __name__ == "__main__":
    sys.stdout.reconfigure(encoding="utf-8", errors="replace")
    sys.stderr.reconfigure(encoding="utf-8", errors="replace")
    raise SystemExit(main())
