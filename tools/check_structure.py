#!/usr/bin/env python3
"""Read-only checks for current links, resource paths and optional code ownership.

Checks local links/heading anchors and literal Godot resource paths. Static
reachability includes native Resource references and the project's editor plugin;
computed paths still require review. Historical production notes are excluded.
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
    "docs/engineering/architecture.md", "docs/status/performance.json",
    "docs/plans/roadmap.md", "docs/plans/foundation-priorities.md",
    "docs/DOCUMENTATION.md", "design/vision.md", "design/rules/README.md",
    "design/README.md", "assets/README.md", "data/README.md",
    "scripts/README.md", "tests/README.md", "tests/kernel_smoke.gd",
)
ROLE_DIRECTORIES = (
    "scripts/sim/kernel", "scripts/presentation",
    "data/definitions", "scripts/sim/definitions/actions", "scripts/sim/definitions/combat",
    "design/rules", "design/systems", "design/research", "docs/plans",
    "docs/status", "docs/engineering", "docs/archive",
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
SOURCE_FOLDERS = ("scripts", "scenes", "tests", "data/definitions", "addons/reol_combat_authoring")
SOURCE_SUFFIXES = frozenset({".gd", ".gdshader", ".tscn", ".tres", ".cfg"})


def heading_anchors(path: Path) -> set[str]:
    """GitHub-style ATX heading slugs, including duplicate-heading suffixes."""
    counts: dict[str, int] = {}
    anchors: set[str] = set()
    fence = ""
    for line in path.read_text(encoding="utf-8-sig").splitlines():
        marker = re.match(r"^ {0,3}(`{3,}|~{3,})", line)
        if marker:
            char = marker.group(1)[0]
            fence = "" if fence == char else char if not fence else fence
            continue
        match = re.match(r"^ {0,3}#{1,6}\s+(.+?)\s*#*\s*$", line)
        if fence or not match:
            continue
        title = re.sub(r"!?\[([^\]]+)\]\([^)]*\)", r"\1", match.group(1))
        title = re.sub(r"<[^>]+>", "", title)
        slug = re.sub(r"[^\w -]", "", title.lower()).replace(" ", "-")
        duplicate = counts.get(slug, 0)
        counts[slug] = duplicate + 1
        anchors.add(f"{slug}-{duplicate}" if duplicate else slug)
    return anchors


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
            if parsed.scheme or parsed.netloc:
                continue
            local = unquote(parsed.path)
            destination = path if not local else root / local.lstrip("/") if local.startswith("/") else path.parent / local
            line = text.count("\n", 0, match.start()) + 1
            if not destination.exists():
                # AGENTS may point to optional, ignored machine-local tooling.
                # A fresh checkout must not require the user's private files.
                if destination.resolve().is_relative_to((root / ".local").resolve()):
                    continue
                issues.append(f"{path.relative_to(root).as_posix()}:{line}: missing Markdown target {target}")
            elif parsed.fragment and destination.suffix.lower() == ".md" and unquote(parsed.fragment) not in heading_anchors(destination):
                issues.append(f"{path.relative_to(root).as_posix()}:{line}: missing Markdown heading {target}")
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


def project_sources(root: Path) -> list[Path]:
    return sorted({root / "project.godot"} | {
        path for folder in SOURCE_FOLDERS for path in (root / folder).rglob("*")
        if path.is_file() and path.suffix in SOURCE_SUFFIXES
    })


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
    sources = project_sources(root)
    for path in sorted(documents):
        issues.extend(check_markdown(path, root))
    for path in sources:
        issues.extend(check_script(path, root))
    for folder in ("scripts", "tests", "addons/reol_combat_authoring"):
        for uid in (root / folder).rglob("*.uid"):
            if not uid.with_suffix("").is_file():
                issues.append(f"{uid.relative_to(root).as_posix()}: orphan UID")
    return issues, len(documents), len(sources)


def audit_code(root: Path) -> list[str]:
    """Suggest review targets; computed paths and external editor calls are unknown.

    This is deliberately not a dead-code deletion tool or a CI gate. Registered
    classes and literal resources provide a conservative, explainable graph.
    """
    sources = {path.relative_to(root).as_posix(): path.read_text(encoding="utf-8-sig")
               for path in project_sources(root)}
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
        if path.endswith("/plugin.cfg"):
            references.update((PurePosixPath(path).parent / script).as_posix()
                              for script in re.findall(r'^script\s*=\s*"([^"]+)"', source, re.M))
        edges[path] = (references & sources.keys()) - {path}
        if path.startswith("scripts/sim/"):
            for target in sorted(edges[path]):
                if target.startswith(("scripts/presentation/", "scripts/entities/")):
                    notes.append(f"REVIEW simulation depends on presentation: {path} -> {target}")
    # Project settings declare autoloads as well as the main scene.
    roots = {"project.godot"} | {path for path in sources if path.startswith(("scenes/", "tests/"))}
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
    print(f"Structure: {document_count} current documents, {script_count} Godot sources, {len(issues)} errors; historical production notes excluded")
    return 1 if issues else 0


if __name__ == "__main__":
    raise SystemExit(main())
