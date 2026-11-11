#!/usr/bin/env python3
"""Read-only checks for current links, resource paths and optional code ownership.

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
    "scripts/README.md", "tests/README.md", "tests/smoke.gd",
)
ROLE_DIRECTORIES = (
    "scripts/sim", "scripts/runtime", "scripts/persistence",
    "data/definitions", "data/scenarios",
    "design/rules", "design/systems", "design/research", "docs/plans",
    "docs/status", "docs/engineering", "docs/specs", "docs/archive",
)
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
        if not (root / relative).exists():
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
        issues.extend(check_markdown(path, root))
    for path in scripts:
        issues.extend(check_script(path, root))
    return issues, len(documents), len(scripts)


def audit_code(root: Path) -> list[str]:
    """Suggest review targets; computed paths and external editor calls are unknown.

    This is deliberately not a dead-code deletion tool or a CI gate. Registered
    classes and literal resources provide a conservative, explainable graph.
    """
    sources = {
        path.relative_to(root).as_posix(): path.read_text(encoding="utf-8-sig")
        for folder in ("scripts", "scenes", "tests")
        for path in (root / folder).rglob("*")
        if path.is_file() and path.suffix in {".gd", ".tscn", ".tres"}
    }
    classes: dict[str, str] = {}
    notes: list[str] = []
    for path, source in sources.items():
        match = re.search(r"^class_name\s+(\w+)", source, re.M)
        if match:
            name = match.group(1)
            if name in classes:
                notes.append(f"REVIEW duplicate class {name}: {classes[name]}, {path}")
            classes[name] = path
        if path.endswith(".gd") and not (root / (path + ".uid")).is_file():
            notes.append(f"REVIEW missing script UID: {path}")
    edges: dict[str, set[str]] = {}
    for path, source in sources.items():
        text = re.sub(r"#[^\n]*", "", source)
        words = set(re.findall(r"\b\w+\b", text))
        references = {classes[name] for name in words & classes.keys()}
        references.update(re.findall(r'res://([^"\s)]+)', text))
        edges[path] = (references & sources.keys()) - {path}
        if path.startswith("scripts/sim/"):
            for target in sorted(edges[path]):
                if target.startswith(("scripts/runtime/", "scripts/entities/", "scripts/world/", "scripts/ui/")):
                    notes.append(f"REVIEW simulation depends on presentation: {path} -> {target}")
    # All checked-in scenes are deliberate entries, including the temporary
    # crowd scene. Tests and autoloads are separate from ordinary gameplay.
    roots = {path for path in sources if path.startswith(("scenes/", "tests/", "scripts/autoload/"))}
    visited: set[str] = set()
    pending = list(roots)
    while pending:
        path = pending.pop()
        if path in visited:
            continue
        visited.add(path)
        pending.extend(edges[path] - visited)
    for path in sorted(sources.keys() - visited):
        notes.append(f"REVIEW no static entry path (may be dynamic): {path}")
    count = sum(path.startswith("scripts/") for path in sources)
    notes.insert(0, f"Code audit: {count} source files, {len(classes)} registered classes; suggestions only")
    return notes


def main(argv: list[str] | None = None) -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("project_dir", nargs="?", type=Path, default=ROOT)
    parser.add_argument("--audit-code", action="store_true", help="show static reachability, UID and dependency review targets; never deletes files")
    args = parser.parse_args(argv)
    root = args.project_dir.resolve()
    if not root.is_dir():
        parser.error(f"not a directory: {root}")
    try:
        issues, document_count, script_count = check_project(root)
        notes = audit_code(root) if args.audit_code else []
    except (OSError, UnicodeError) as error:
        print(f"ERROR: cannot read project: {error}")
        return 1
    for issue in issues:
        print(f"ERROR {issue}")
    for note in notes:
        print(note)
    print(f"Structure: {document_count} current documents, {script_count} scripts, {len(issues)} errors; archive excluded")
    return 1 if issues else 0


if __name__ == "__main__":
    raise SystemExit(main())
