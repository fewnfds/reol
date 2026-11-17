#!/usr/bin/env python3
"""Exercise the restored read-only checker with isolated Godot text projects."""

from pathlib import Path
import json
import subprocess
import sys
import tempfile


CHECKER = Path(__file__).with_name("check_godot_project.py")
PROJECT = 'config_version=5\n[application]\nrun/main_scene="res://main.tscn"\n'
SCENE = '[gd_scene format=3]\n[node name="Root" type="Node"]\n'
RESOURCE = '[gd_resource type="Resource" format=3 uid="uid://babc"]\n[resource]\n'


def check(files: dict[str, str], strict: bool = False) -> tuple[int, dict]:
    # TemporaryDirectory owns only this newly created project, never a user save.
    with tempfile.TemporaryDirectory(prefix="reol-resource-check-") as temporary:
        root = Path(temporary)
        for relative, content in {"project.godot": PROJECT, "main.tscn": SCENE, **files}.items():
            target = root / relative
            if not target.resolve().is_relative_to(root.resolve()):
                raise ValueError("fixture escaped temporary project")
            target.parent.mkdir(parents=True, exist_ok=True)
            target.write_text(content, encoding="utf-8")
        command = [sys.executable, "-X", "utf8", str(CHECKER), str(root), "--json", "--max-issues", "0"]
        if strict:
            command.append("--strict")
        result = subprocess.run(command, capture_output=True, text=True, encoding="utf-8", timeout=15)
        return result.returncode, json.loads(result.stdout)


def expect(files: dict[str, str], codes: set[str], exit_code: int, strict: bool = False) -> None:
    actual_exit, report = check(files, strict)
    found = {item["code"] for group in ("errors", "warnings") for item in report[group]}
    if actual_exit != exit_code or found != codes or report["truncated"]:
        raise AssertionError((actual_exit, report, codes, exit_code))


def main() -> None:
    expect({}, set(), 0)
    expect({"A.tres": RESOURCE, "B.tres": RESOURCE}, {"uid-duplicate"}, 1)
    ext_scene = '[gd_scene format=3]\n[ext_resource type="Resource" path="res://%s" id="1"]\n[node name="Root" type="Node"]\n'
    expect({"main.tscn": ext_scene % "data.tres", "Data.tres": RESOURCE}, {"path-case-mismatch"}, 1)
    expect({"main.tscn": SCENE + 'material = SubResource("missing")\n'}, {"sub-resource-id-undeclared"}, 1)
    expect({"Data.tres": '[gd_resource type="Resource" format=3]\n[sub_resource type="Resource" id="first"]\nmetadata/next = SubResource("later")\n[sub_resource type="Resource" id="later"]\n[resource]\n'}, {"sub-resource-used-before-declared"}, 1)
    expect({"main.tscn": SCENE + '[connection signal="ready" from="Missing" to="." method="x"]\n'}, {"connection-node-missing"}, 1)
    expect({"main.tscn": SCENE + '[node name="Child" type="Node" parent="Missing"]\n'}, {"node-parent-missing"}, 1)
    stale = '[gd_scene format=3]\n[ext_resource type="Resource" uid="uid://babc" path="res://Old.tres" id="1"]\n[node name="Root" type="Node"]\n'
    expect({"main.tscn": stale, "Data.tres": RESOURCE}, {"ext-resource-path-stale"}, 0)
    expect({"main.tscn": stale, "Data.tres": RESOURCE}, {"ext-resource-path-stale"}, 1, strict=True)
    expect({"old.gd.uid": "uid://babd\n"}, {"uid-file-orphaned"}, 0)
    ignored = {"ignored/.gdignore": "", "ignored/bad.tscn": SCENE + 'material = SubResource("missing")\n'}
    expect(ignored, set(), 0)
    print("PASS: 11 isolated cases (valid, UID, case, references, tree, warning/strict, ignored directory)")


if __name__ == "__main__":
    main()
