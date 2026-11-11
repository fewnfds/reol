#!/usr/bin/env python3
"""Reol Godot CLI helper.

Cross-platform wrapper used by humans, AI agents, and the MCP bridge.

Examples:
    python tools/godot.py doctor
    python tools/godot.py import
    python tools/godot.py test
    python tools/godot.py run --headless --quit-after 120
    python tools/godot.py editor
    python tools/godot.py export --preset "Windows Desktop" --output build/windows/reol.exe
"""

from __future__ import annotations

import argparse
import os
import platform
import queue
import re
import shutil
import subprocess
import sys
import threading
import time
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
LOG_DIR = ROOT / "logs"

EXE_SUFFIXES = {".exe", ".bin", ""}


# ---------------------------------------------------------------------------
# Godot discovery
# ---------------------------------------------------------------------------


def _candidate_roots() -> list[Path]:
    roots: list[Path] = []
    home = Path.home()
    local = Path(os.environ.get("LOCALAPPDATA", home / "AppData" / "Local"))

    if os.name == "nt":
        roots += [
            Path(r"C:\Program Files\Godot"),
            Path(r"C:\Program Files (x86)\Godot"),
            local / "Programs" / "Godot",
            local / "Microsoft" / "WinGet" / "Packages",
            home / "scoop" / "apps" / "godot" / "current",
            home / "Downloads",
            home / "Desktop",
            Path(r"D:\Tools\Godot"),
            Path(r"D:\Godot"),
            Path(r"D:\Program Files\Godot"),
            Path(r"C:\Program Files (x86)\Steam\steamapps\common\Godot Engine"),
            Path(r"D:\SteamLibrary\steamapps\common\Godot Engine"),
        ]
    elif sys.platform == "darwin":
        roots += [
            Path("/Applications"),
            home / "Applications",
            Path("/opt/homebrew/bin"),
            Path("/usr/local/bin"),
        ]
    else:
        roots += [
            Path("/usr/bin"),
            Path("/usr/local/bin"),
            Path("/opt/godot"),
            home / ".local" / "bin",
            home / ".steam" / "steam" / "steamapps" / "common" / "Godot Engine",
        ]

    return roots


def _scan_dir(root: Path, depth: int = 1) -> list[Path]:
    """Find Godot executables in root, without a full-disk crawl."""
    if not root.exists():
        return []

    results: list[Path] = []
    skip = {"node_modules", ".git", ".godot", "addons", "migration_payload"}

    def scan(directory: Path, remaining: int) -> None:
        try:
            entries = list(directory.iterdir())
        except OSError:
            return
        for entry in entries:
            try:
                if entry.is_file():
                    name = entry.name.lower()
                    suffix = entry.suffix.lower()
                    if "godot" in name and suffix in EXE_SUFFIXES:
                        results.append(entry)
                elif entry.is_dir() and remaining > 0:
                    if entry.name.lower() in skip:
                        continue
                    scan(entry, remaining - 1)
            except OSError:
                continue

    scan(root, depth)
    return results


def _env_godot() -> Path | None:
    for var in ("GODOT_BIN", "GODOT_PATH", "GODOT4"):
        value = os.environ.get(var)
        if not value:
            continue
        path = Path(value).expanduser()
        if path.is_dir():
            found = _scan_dir(path, 1)
            if found:
                return sorted(found, key=lambda p: p.name.lower(), reverse=True)[0]
        if path.is_file():
            return path
        which = shutil.which(value)
        if which:
            return Path(which)
    return None


def find_godot() -> Path | None:
    """Return the Godot executable path, or None."""
    env_path = _env_godot()
    if env_path:
        return env_path

    for name in ("godot", "godot4", "Godot"):
        which = shutil.which(name)
        if which:
            return Path(which)

    if sys.platform == "darwin":
        app = Path("/Applications/Godot.app/Contents/MacOS/Godot")
        if app.is_file():
            return app

    found: list[Path] = []
    for root in _candidate_roots():
        depth = 4 if "winget" in str(root).lower() else 2
        found.extend(_scan_dir(root, depth))

    if not found:
        return None

    # Prefer the highest-looking version name.
    def version_key(path: Path) -> tuple:
        numbers = re.findall(r"\d+", path.name)
        return tuple(int(n) for n in numbers[:3]) if numbers else (0,)

    return sorted(found, key=version_key, reverse=True)[0]


def godot_version(path: Path) -> str | None:
    try:
        proc = subprocess.run(
            [str(path), "--version"],
            cwd=ROOT,
            capture_output=True,
            text=True,
            encoding="utf-8",
            errors="replace",
            timeout=15,
        )
    except (OSError, subprocess.TimeoutExpired):
        return None
    text = (proc.stdout or "") + (proc.stderr or "")
    match = re.search(r"(\d+\.\d+(?:\.\d+)?)", text)
    return match.group(1) if match else None


# ---------------------------------------------------------------------------
# Commands
# ---------------------------------------------------------------------------


def _require_godot() -> Path | None:
    path = find_godot()
    if path is None:
        print("ERROR: Godot executable not found.", file=sys.stderr)
        print("Install Godot 4.7.2 and set GODOT_BIN, e.g.:", file=sys.stderr)
        print(
            r'  [Environment]::SetEnvironmentVariable("GODOT_BIN", "D:\Tools\Godot\Godot_v4.7.2-stable_win64.exe", "User")',
            file=sys.stderr,
        )
        print("Then reopen the terminal and run: python tools/godot.py doctor", file=sys.stderr)
        return None
    return path


def _run(cmd: list[str], name: str, timeout: float | None = None, *, fail_fast: bool = True, on_start=None) -> int:
    """Stream one owned process; errors/timeouts retain the log and stop promptly."""
    LOG_DIR.mkdir(parents=True, exist_ok=True)
    (LOG_DIR / ".gdignore").touch(exist_ok=True)
    log_path = LOG_DIR / f"{name}-{time.strftime('%Y%m%d-%H%M%S')}-{time.time_ns() % 1000000000}.log"
    print("$ " + " ".join(map(str, cmd)), flush=True)
    with log_path.open("w", encoding="utf-8", buffering=1) as log:
        def record(line: str) -> None:
            log.write(line if line.endswith("\n") else line + "\n")
            print(line.rstrip("\r\n"), flush=True)

        try:
            # A newly exported Windows executable may briefly be held by the
            # host scanner. Retry only that sharing violation, for at most 3s.
            for attempt in range(7):
                try:
                    child = subprocess.Popen(cmd, cwd=ROOT, stdout=subprocess.PIPE,
                                             stderr=subprocess.STDOUT, text=True,
                                             encoding="utf-8", errors="replace")
                    break
                except OSError as transient:
                    if getattr(transient, "winerror", None) != 32 or attempt == 6:
                        raise
                    time.sleep(0.5)
        except OSError as error:
            record(f"ERROR: cannot start process: {error}")
            return 127
        if on_start is not None:
            on_start(child.pid)
        events: queue.Queue[str | None] = queue.Queue()

        def read() -> None:
            for line in child.stdout:
                events.put(line)
            child.wait()
            events.put(None)

        reader = threading.Thread(target=read, daemon=True)
        reader.start()
        deadline = time.monotonic() + timeout if timeout is not None else None
        code: int | None = None
        errors = False
        try:
            while True:
                remaining = max(0, deadline - time.monotonic()) if deadline is not None else None
                try:
                    line = events.get(timeout=remaining)
                except queue.Empty:
                    record(f"ERROR: timed out after {timeout:g}s")
                    code = 124
                    break
                if line is None:
                    break
                record(line)
                plain = re.sub(r"\x1b\[[0-?]*[ -/]*[@-~]", "", line).lstrip()
                if plain.startswith(("SCRIPT ERROR:", "ERROR:", "FAIL ")):
                    errors = True
                    if fail_fast:
                        code = 1
                        break
        finally:
            if child.poll() is None:
                child.kill()
            child.wait()
            reader.join(timeout=1)
            if not reader.is_alive():
                child.stdout.close()
            # Preserve the final buffered lines after failure/timeout as evidence.
            while not events.empty():
                line = events.get_nowait()
                if line is not None:
                    record(line)
            print(f"[log] {log_path}", flush=True)
        return code if code is not None else child.returncode or int(errors)


def cmd_doctor(_args: argparse.Namespace) -> int:
    print("Reol - Godot environment")
    print(f"Project:  {ROOT}")
    print(f"Python:   {platform.python_version()} ({sys.executable})")
    print(f"Platform: {platform.platform()}")
    print(f"GODOT_BIN: {os.environ.get('GODOT_BIN', '(not set)')}")

    path = find_godot()
    if path is None:
        print("Godot:    NOT FOUND")
        print("")
        print("Install Godot 4.7.2 (standard, not .NET) and set GODOT_BIN.")
        print("See docs/engineering/tooling/usage.md.")
        return 1

    version = godot_version(path)
    print(f"Godot:    {path}")
    print(f"Version:  {version or '(unknown)'}")

    checks = [
        ("project.godot", ROOT / "project.godot"),
        (".godot/ import cache", ROOT / ".godot"),
        ("addons/godot_ai", ROOT / "addons" / "godot_ai" / "plugin.cfg"),
        ("tests/smoke.gd", ROOT / "tests" / "smoke.gd"),
        (".agents/skills", ROOT / ".agents" / "skills"),
        (".codex/config.toml", ROOT / ".codex" / "config.toml"),
    ]
    for label, path_to_check in checks:
        print(f"{label + ':':<22} {'yes' if path_to_check.exists() else 'no'}")

    if version and not version.startswith("4.7"):
        print("WARNING: project targets Godot 4.7.x; found a different version.")
    return 0


def cmd_which(_args: argparse.Namespace) -> int:
    path = find_godot()
    if path is None:
        return 1
    print(path)
    return 0


def cmd_version(_args: argparse.Namespace) -> int:
    path = _require_godot()
    if path is None:
        return 1
    version = godot_version(path)
    if version is None:
        print("ERROR: could not read Godot version.", file=sys.stderr)
        return 1
    print(version)
    return 0


def cmd_import(_args: argparse.Namespace) -> int:
    godot = _require_godot()
    if godot is None:
        return 1
    return _run(
        [str(godot), "--headless", "--path", str(ROOT), "--quiet", "--import"],
        "import",
        timeout=600,
    )


def cmd_test(args: argparse.Namespace) -> int:
    godot = _require_godot()
    if godot is None:
        return 1
    command = [str(godot), "--headless", "--path", str(ROOT),
               "--script", "res://tests/smoke.gd", "--"]
    for suite in args.suite:
        command.extend(["--suite", suite])
    if args.list_suites:
        command.append("--list-suites")
    return _run(command, "smoke", timeout=args.timeout)


def cmd_run(args: argparse.Namespace) -> int:
    godot = _require_godot()
    if godot is None:
        return 1
    cmd = [str(godot), "--path", str(ROOT)]
    if args.headless:
        cmd.append("--headless")
    if args.quit_after is not None:
        cmd.extend(["--quit-after", str(args.quit_after)])
    cmd.extend(args.extra)
    return _run(cmd, "run", fail_fast=False)


def cmd_editor(_args: argparse.Namespace) -> int:
    godot = _require_godot()
    if godot is None:
        return 1
    return _run([str(godot), "--editor", "--path", str(ROOT)], "editor", fail_fast=False)


def cmd_export(args: argparse.Namespace) -> int:
    godot = _require_godot()
    if godot is None:
        return 1
    output = Path(args.output)
    if not output.is_absolute():
        output = ROOT / output
    output.parent.mkdir(parents=True, exist_ok=True)
    return _run(
        [
            str(godot),
            "--headless",
            "--path",
            str(ROOT),
            "--export-release",
            args.preset,
            str(output),
        ],
        "export",
        timeout=1200,
    )


def _short_timeout(value: str) -> int:
    try:
        seconds = int(value)
    except ValueError as error:
        raise argparse.ArgumentTypeError("use 1..30 seconds for a short check") from error
    if not 1 <= seconds <= 30:
        raise argparse.ArgumentTypeError("use 1..30 seconds; reduce an overlong check instead")
    return seconds


def build_parser() -> argparse.ArgumentParser:
    parser = argparse.ArgumentParser(
        description="Reol Godot CLI helper.",
        formatter_class=argparse.RawDescriptionHelpFormatter,
    )
    sub = parser.add_subparsers(dest="command", required=True)

    sub.add_parser("doctor", help="show environment status").set_defaults(func=cmd_doctor)
    sub.add_parser("which", help="print the Godot executable path").set_defaults(func=cmd_which)
    sub.add_parser("version", help="print the Godot version").set_defaults(func=cmd_version)
    sub.add_parser("import", help="headless import resources").set_defaults(func=cmd_import)
    test = sub.add_parser("test", help="run the small local smoke checks; old full check/CI retired")
    test.add_argument("--suite", action="append", default=[], choices=("settlement", "actor_batch", "inventory", "input", "presentation", "spatial", "elements"))
    test.add_argument("--list-suites", action="store_true")
    test.add_argument("--timeout", type=_short_timeout, default=15, metavar="SECONDS")
    test.set_defaults(func=cmd_test)

    run = sub.add_parser("run", help="run the project")
    run.add_argument("--headless", action="store_true", help="no window")
    run.add_argument("--quit-after", type=int, default=None, help="quit after N frames")
    run.add_argument("extra", nargs=argparse.REMAINDER, help="extra args passed to Godot")
    run.set_defaults(func=cmd_run)

    sub.add_parser("editor", help="open the editor").set_defaults(func=cmd_editor)

    export = sub.add_parser("export", help="export a release build")
    export.add_argument("--preset", required=True, help='export preset name, e.g. "Windows Desktop"')
    export.add_argument("--output", required=True, help="output path")
    export.set_defaults(func=cmd_export)

    return parser


def main() -> int:
    parser = build_parser()
    args = parser.parse_args()
    return int(args.func(args))


if __name__ == "__main__":
    raise SystemExit(main())
