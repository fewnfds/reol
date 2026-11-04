#!/usr/bin/env python3
"""Create project-local Codex MCP entries using this checkout's absolute paths.

Context7 is enabled by default; Coding-Solo godot is a disabled backup.
Existing server entries and other settings are preserved. Godot AI configures
its own authenticated bridge from the editor dock. Inherited langchain-docs
is not managed: a disabled-only override needs a compatible inherited
transport, and an unconditional transport can conflict with a custom server.
This script checks the project file only; use codex mcp list to check the
effective configuration and same-name inherited transport compatibility.
"""

from __future__ import annotations

import argparse
import copy
import json
import re
import shutil
import sys
import tempfile
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
            "enabled": False,
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


def enable_generated_backup(original: str, data: dict) -> str | None:
    """Change only a recognizable backup flag, after verifying the full TOML diff."""
    header = re.compile(r"(?m)^[ \t]*\[mcp_servers\.godot\][ \t]*(?:#[^\r\n]*)?(?:\r?\n|$)")
    headers = list(header.finditer(original))
    if len(headers) != 1:
        return None
    section_start = headers[0].end()
    next_header = re.search(r"(?m)^[ \t]*\[\[?[^\r\n]*\]\]?[ \t]*(?:#[^\r\n]*)?$", original[section_start:])
    section_end = section_start + next_header.start() if next_header else len(original)
    section = original[section_start:section_end]
    enabled = list(re.finditer(r"(?m)^([ \t]*enabled[ \t]*=[ \t]*)false([ \t]*(?:#[^\r\n]*)?)(?=\r?$)", section))
    if len(enabled) != 1:
        return None
    match = enabled[0]
    start = section_start + match.start()
    end = section_start + match.end()
    updated = original[:start] + match.group(1) + "true" + match.group(2) + original[end:]
    expected = copy.deepcopy(data)
    expected["mcp_servers"]["godot"]["enabled"] = True
    try:
        return updated if tomllib.loads(updated) == expected else None
    except tomllib.TOMLDecodeError:
        return None


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    parser.add_argument("--check", action="store_true", help="Check the requested state without writing")
    parser.add_argument(
        "--enable-backup-godot", action="store_true",
        help="Enable the generated Coding-Solo godot backup; with --check, only verify it is enabled",
    )
    args = parser.parse_args()

    skills = sorted((ROOT / ".agents" / "skills").glob("*/SKILL.md"))
    if not skills:
        print("ERROR: No project skills found in .agents/skills", file=sys.stderr)
        return 1
    print(f"Project skills: {len(skills)} ({ROOT / '.agents' / 'skills'})")

    try:
        original = ""
        if CONFIG.exists():
            with CONFIG.open(encoding="utf-8", newline="") as stream:
                original = stream.read()
        data = tomllib.loads(original)
    except (OSError, tomllib.TOMLDecodeError) as exc:
        print(f"ERROR: Cannot read {CONFIG}: {exc}", file=sys.stderr)
        return 1

    existing = data.get("mcp_servers", {})
    if not isinstance(existing, dict):
        print("ERROR: mcp_servers is not a table; existing config preserved", file=sys.stderr)
        return 1
    additions: list[str] = []
    problems: list[str] = []
    updated = original
    changes_backup = False
    for name, expected in expected_servers().items():
        if name not in existing:
            if name == "godot" and args.enable_backup_godot:
                expected["enabled"] = True
            additions.append(render_server(name, expected))
            print(f"{'MISSING' if args.check else 'ADD'} MCP: {name}")
            continue
        current = existing[name]
        if not isinstance(current, dict):
            problems.append(f"{name}: existing entry is not a table")
            continue
        if "enabled" in current and not isinstance(current["enabled"], bool):
            problems.append(f"{name}: enabled is not a boolean")
            continue
        custom = any(current.get(key) != expected[key] for key in ("command", "args", "cwd", "url") if key in expected)
        custom |= any(key in current and key not in expected for key in ("command", "url"))
        state = "disabled" if current.get("enabled", True) is False else "enabled"
        print(f"PRESENT MCP: {name} ({state}{', custom connection' if custom else ''}; preserved)")
        if name == "godot" and args.enable_backup_godot:
            if custom:
                problems.append("godot: custom connection is not the generated backup; enable it manually if intended")
            elif state == "disabled":
                candidate = enable_generated_backup(original, data)
                if candidate is None:
                    problems.append("godot: cannot safely edit the existing flag; set enabled = true manually")
                else:
                    updated = candidate
                    changes_backup = True
                    print(f"{'DISABLED' if args.check else 'ENABLE'} MCP backup: godot")

    print("langchain-docs: inherited server is not managed by this script; a safe project override depends on its transport.")

    if problems:
        for problem in problems:
            print(f"ERROR: {problem}; existing entry preserved", file=sys.stderr)
        return 1
    if additions or changes_backup:
        newline = "\r\n" if "\r\n" in original else "\n"
        if additions:
            separator = "" if not updated else newline if updated.endswith(("\n", "\r")) else newline * 2
            updated += separator + newline.join(block.replace("\n", newline) for block in additions)
        try:
            tomllib.loads(updated)
        except tomllib.TOMLDecodeError as exc:
            print(f"ERROR: Cannot safely append MCP entries: {exc}; existing config preserved", file=sys.stderr)
            return 1
    if args.check and (additions or changes_backup):
        suffix = " --enable-backup-godot" if args.enable_backup_godot else ""
        print(f"Run: python tools/setup_codex.py{suffix}")
        return 1
    if additions or changes_backup:
        CONFIG.parent.mkdir(parents=True, exist_ok=True)
        if CONFIG.exists():
            stamp = time.strftime("%Y%m%d-%H%M%S")
            backup = CONFIG.with_name(f"config.toml.{stamp}-{time.time_ns()}.bak")
            shutil.copy2(CONFIG, backup)
            print(f"Backup: {backup}")
        temporary: Path | None = None
        try:
            with tempfile.NamedTemporaryFile(
                mode="w", encoding="utf-8", newline="", dir=CONFIG.parent,
                prefix="config.toml.", suffix=".tmp", delete=False,
            ) as stream:
                temporary = Path(stream.name)
                stream.write(updated)
            if CONFIG.exists():
                shutil.copymode(CONFIG, temporary)
            temporary.replace(CONFIG)
        finally:
            if temporary is not None:
                temporary.unlink(missing_ok=True)
        print(f"Wrote: {CONFIG}")
    print("Managed Codex project entries OK (takes effect when Codex reloads the project).")
    print("Coding-Solo backup: set enabled = true or use --enable-backup-godot to enable the generated entry.")
    print("Check effective inherited servers and transports with: codex mcp list")
    print("Godot AI: use Godot AI dock -> Configure -> Codex; no manual ports.")
    return 0


if __name__ == "__main__":
    sys.stdout.reconfigure(encoding="utf-8", errors="replace")
    sys.stderr.reconfigure(encoding="utf-8", errors="replace")
    raise SystemExit(main())
