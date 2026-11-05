#!/usr/bin/env python3
"""Read-only checks for Reol's current documentation and migrated file layout.

This supplements the existing Godot scene/UID checker; it does not parse scenes
or promise to resolve computed resource paths or Markdown heading anchors.
Archived documents keep their historical paths and are excluded deliberately.
"""

from __future__ import annotations

import argparse
from pathlib import Path, PurePosixPath
import re
from urllib.parse import unquote, urlsplit


ROOT = Path(__file__).resolve().parents[1]
ENTRY_FILES = (
    "project.godot", "README.md", "AGENTS.md", "docs/README.md",
    "docs/status/handoff.md", "docs/status/baseline.md", "docs/status/features.md",
    "docs/engineering/project-structure.md", "docs/engineering/architecture.md",
    "docs/plans/roadmap.md", "docs/plans/foundation-priorities.md",
    "docs/DOCUMENTATION.md", "design/vision.md", "design/rules/README.md",
    "design/README.md", "assets/README.md", "data/README.md",
    "scripts/README.md", "tests/README.md", "tests/run_tests.gd",
)
ROLE_DIRECTORIES = (
    "scripts/sim", "scripts/runtime", "scripts/persistence",
    "data/definitions", "data/scenarios", "tests/sim", "tests/runtime",
    "design/rules", "design/systems", "design/research", "docs/plans",
    "docs/status", "docs/engineering", "docs/specs", "docs/archive",
)
MAX_ACTIVE_DOCUMENT_BYTES = 16 * 1024
MOVED_PATHS = {
    "scripts/sim/village_runtime.gd": "scripts/runtime/village_runtime.gd",
    "scripts/sim/world_continuity_runtime.gd": "scripts/runtime/world_continuity_runtime.gd",
    "scripts/sim/save_store.gd": "scripts/persistence/save_store.gd",
    "data/simulation.json": "data/scenarios/village.json",
    "data/world_continuity.json": "data/scenarios/world_continuity.json",
    **{f"data/{name}.json": f"data/definitions/{name}.json"
       for name in ("pawns", "origins", "ranks")},
    **{f"tests/{name}.gd": f"tests/sim/{name}.gd" for name in (
        "test_regional_simulation", "test_sim_ledgers", "test_sim_schema",
        "test_social_memory", "test_village_batch", "test_village_simulation",
    )},
    **{f"tests/{name}.gd": f"tests/runtime/{name}.gd" for name in (
        "test_village_navigation", "test_village_runtime", "test_world_continuity_runtime",
    )},
}
LINK = re.compile(
    r"!?\[[^\]\n]*\]\(\s*(?:<(?P<angle>[^>\n]+)>|"
    r"(?P<plain>(?:\\.|[^\s()\\]|\([^()\n]*\))+))"
    r"(?:\s+(?:\"[^\"\n]*\"|'[^'\n]*'|\([^()\n]*\)))?\s*\)"
)
REFERENCE = re.compile(
    r"^ {0,3}\[[^\]\n]+\]:\s*(?:<(?P<angle>[^>\n]+)>|(?P<plain>\S+))", re.M
)
GD_TOKEN = re.compile(r'''\#[^\n]*|"(?:\\.|[^"\\])*"|'(?:\\.|[^'\\])*' ''', re.X)
# These are runtime outputs, not checked-in Godot source assets. In a fresh
# checkout the directory itself may not exist until a test writes its output.
GENERATED_RESOURCE_ROOTS = frozenset({"logs"})


def _without_code(text: str) -> str:
    """Mask examples while keeping line numbers useful in diagnostics."""
    output: list[str] = []
    fence: str = ""
    fence_size = 0
    for line in text.splitlines(keepends=True):
        marker = re.match(r"^\s{0,3}(`{3,}|~{3,})", line)
        if marker:
            run = marker.group(1)
            if not fence:
                fence, fence_size = run[0], len(run)
            elif run[0] == fence and len(run) >= fence_size:
                fence = ""
            output.append("\n" if line.endswith("\n") else "")
        elif fence or line.startswith(("    ", "\t")):
            output.append("\n" if line.endswith("\n") else "")
        else:
            output.append(line)
    return re.sub(r"(`+)([^\n]*?)\1", lambda match: " " * len(match.group()), "".join(output))


def check_markdown(path: Path, root: Path) -> list[str]:
    text = _without_code(path.read_text(encoding="utf-8-sig"))
    issues: list[str] = []
    for pattern in (LINK, REFERENCE):
        for match in pattern.finditer(text):
            target = match.group("angle") or match.group("plain")
            target = re.sub(r"\\([() ])", r"\1", target)
            parsed = urlsplit(target)
            if parsed.scheme or parsed.netloc or not parsed.path:
                continue
            local = unquote(parsed.path)
            destination = root / local.lstrip("/") if local.startswith("/") else path.parent / local
            if not destination.exists():
                line = text.count("\n", 0, match.start()) + 1
                issues.append(f"{path.relative_to(root).as_posix()}:{line}: missing Markdown target {target}")
    return issues


def check_script(path: Path, root: Path) -> list[str]:
    """Check literal source paths, excluding explicitly generated outputs."""
    text = path.read_text(encoding="utf-8-sig")
    issues: list[str] = []
    for match in GD_TOKEN.finditer(text):
        literal = match.group()
        if literal.startswith("#") or not literal[1:-1].startswith("res://"):
            continue
        relative = literal[1:-1].removeprefix("res://")
        if not relative or any(token in relative for token in ("%", "{", "*")):
            continue
        # Do not exempt paths escaping the output directory or similarly named
        # source directories. Godot resource paths use forward slashes.
        parts = PurePosixPath(relative).parts
        if "\\" not in relative and parts and parts[0] in GENERATED_RESOURCE_ROOTS and ".." not in parts:
            continue
        line = text.count("\n", 0, match.start()) + 1
        where = f"{path.relative_to(root).as_posix()}:{line}"
        if relative in MOVED_PATHS:
            issues.append(f"{where}: moved res://{relative}; use res://{MOVED_PATHS[relative]}")
        elif not (root / relative).exists():
            issues.append(f"{where}: missing resource res://{relative}")
    return issues


def check_project(root: Path) -> tuple[list[str], int, int]:
    issues: list[str] = []
    for name in ENTRY_FILES:
        if not (root / name).is_file():
            issues.append(f"{name}: missing project entry point")
    for name in ROLE_DIRECTORIES:
        if not (root / name).is_dir():
            issues.append(f"{name}: missing responsibility directory")
    documents = set(root.glob("*.md"))
    for name in ("docs", "design"):
        documents.update(
            path for path in (root / name).rglob("*.md")
            if not (name == "docs" and "archive" in path.relative_to(root / name).parts)
        )
    for name in ("assets", "data", "scripts", "tests"):
        if (root / name / "README.md").is_file():
            documents.add(root / name / "README.md")
    scripts = sorted(path for name in ("scripts", "tests") for path in (root / name).rglob("*.gd"))
    for path in sorted(documents):
        relative = path.relative_to(root).as_posix()
        # Evidence retains its original scope and wording; current guidance
        # must instead be split into independently readable topic pages.
        if not relative.startswith("docs/qa/") and path.stat().st_size > MAX_ACTIVE_DOCUMENT_BYTES:
            issues.append(f"{relative}: active document exceeds {MAX_ACTIVE_DOCUMENT_BYTES} bytes; split by topic")
        issues.extend(check_markdown(path, root))
    for path in scripts:
        issues.extend(check_script(path, root))
    return issues, len(documents), len(scripts)


def main(argv: list[str] | None = None) -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("project_dir", nargs="?", type=Path, default=ROOT)
    args = parser.parse_args(argv)
    root = args.project_dir.resolve()
    if not root.is_dir():
        parser.error(f"not a directory: {root}")
    try:
        issues, document_count, script_count = check_project(root)
    except (OSError, UnicodeError) as error:
        print(f"ERROR: cannot read project: {error}")
        return 1
    for issue in issues:
        print(f"ERROR {issue}")
    print(f"Structure: {document_count} current documents, {script_count} scripts, {len(issues)} errors; archive excluded")
    return 1 if issues else 0


if __name__ == "__main__":
    raise SystemExit(main())
