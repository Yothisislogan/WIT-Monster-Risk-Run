#!/usr/bin/env python3
"""Validate hand-authored .tscn text and the node paths scripts use to reach it.

Every scene in this project is written by hand as text, and there is no Godot
binary here to open one and tell us it is wrong. A scene with a bad
`load_steps` count, a `SubResource` that was never declared, or a `parent=`
pointing at a node that does not exist fails at load time -- and a `$Node`
path or `%UniqueName` that does not resolve fails at _ready() with a null,
usually as a confusing "attempt to call function on a null instance" a long
way from the typo.

Checks, per scene:

  * load_steps equals the number of ext_resource + sub_resource blocks, plus 1
  * every ExtResource("id") and SubResource("id") used is declared
  * sub_resources are declared before they are referenced by another
  * every ext_resource path exists on disk
  * every node's parent= path was declared earlier in the file
  * uid= values are unique across all scenes

And, per script attached to a node in a scene:

  * every `$Path` / `$Path/Sub` the script uses resolves from that node
  * every `%UniqueName` resolves to a node with unique_name_in_owner = true

Run from the repository root:  python3 tools/check_scenes.py
"""

from __future__ import annotations

import re
import sys
from pathlib import Path

ROOT = Path(__file__).resolve().parent.parent

HEADER = re.compile(r'^\[gd_scene(?P<attrs>[^\]]*)\]', re.MULTILINE)
BLOCK = re.compile(r'^\[(?P<kind>ext_resource|sub_resource|node|connection)(?P<attrs>[^\]]*)\]',
                   re.MULTILINE)
ATTR = re.compile(r'(\w+)="([^"]*)"')
EXT_USE = re.compile(r'ExtResource\("([^"]+)"\)')
SUB_USE = re.compile(r'SubResource\("([^"]+)"\)')

# `$Node`, `$Node/Child`. Anything quoted, absolute, or with .. is skipped --
# those are legitimate and not worth the false positives.
DOLLAR_PATH = re.compile(r'\$([A-Za-z_][A-Za-z0-9_]*(?:/[A-Za-z_][A-Za-z0-9_]*)*)')
UNIQUE_USE = re.compile(r'%([A-Za-z_][A-Za-z0-9_]*)')
# "COVERAGE %d / %d" is a format string, not a reference to a node called `d`.
# String bodies have to go before either pattern is applied.
STRING_LITERAL = re.compile(r'"(?:[^"\\]|\\.)*"' r"|'(?:[^'\\]|\\.)*'")


def strip_code(line: str) -> str:
    """The executable part of a line: no comment, no string bodies."""
    without_strings = STRING_LITERAL.sub('""', line)
    return without_strings.split("#")[0]


class Scene:
    def __init__(self, path: Path):
        self.path = path
        self.rel = str(path.relative_to(ROOT))
        self.text = path.read_text(encoding="utf-8")
        self.problems: list[str] = []
        self.uid = ""
        self.load_steps = 1
        self.ext: dict[str, dict[str, str]] = {}
        self.sub: list[str] = []
        # node path -> {"name", "parent", "unique", "script_id"}
        self.nodes: dict[str, dict[str, str | bool]] = {}
        self._parse()

    def _line_of(self, index: int) -> int:
        return self.text.count("\n", 0, index) + 1

    def _parse(self) -> None:
        header = HEADER.search(self.text)
        if header is None:
            self.problems.append("no [gd_scene] header")
            return
        attrs = dict(ATTR.findall(header.group("attrs")))
        self.uid = attrs.get("uid", "")
        steps = re.search(r"load_steps=(\d+)", header.group("attrs"))
        self.load_steps = int(steps.group(1)) if steps else 1

        blocks = list(BLOCK.finditer(self.text))
        for index, block in enumerate(blocks):
            kind = block.group("kind")
            attrs = dict(ATTR.findall(block.group("attrs")))
            start = block.end()
            end = blocks[index + 1].start() if index + 1 < len(blocks) else len(self.text)
            body = self.text[start:end]
            line = self._line_of(block.start())
            if kind == "ext_resource":
                self.ext[attrs.get("id", "")] = {
                    "path": attrs.get("path", ""), "type": attrs.get("type", ""),
                    "line": str(line)}
            elif kind == "sub_resource":
                self._check_sub_body(body, line)
                self.sub.append(attrs.get("id", ""))
            elif kind == "node":
                self._record_node(attrs, body, line)

    def _check_sub_body(self, body: str, line: int) -> None:
        """A sub_resource may only reference sub_resources declared above it."""
        for used in SUB_USE.findall(body):
            if used not in self.sub:
                self.problems.append(
                    f"{self.rel}:{line}: sub_resource uses SubResource(\"{used}\") "
                    f"before it is declared")

    def _record_node(self, attrs: dict[str, str], body: str, line: int) -> None:
        name = attrs.get("name", "")
        parent = attrs.get("parent")
        if parent is None:
            path = "."          # the root node
        elif parent == ".":
            path = name
        else:
            path = f"{parent}/{name}"
            if parent not in self.nodes:
                self.problems.append(
                    f"{self.rel}:{line}: node '{name}' has parent=\"{parent}\", "
                    f"which is not a node declared earlier in this scene")
        script = EXT_USE.search(body[body.find("script ="):]) if "script =" in body else None
        self.nodes[path] = {
            "name": name,
            "unique": "unique_name_in_owner = true" in body,
            "script_id": script.group(1) if script else "",
            "line": str(line),
        }

    def check(self) -> None:
        actual = len(self.ext) + len(self.sub) + 1
        if self.load_steps != actual:
            self.problems.append(
                f"{self.rel}:1: load_steps={self.load_steps} but the scene declares "
                f"{len(self.ext)} ext_resource + {len(self.sub)} sub_resource "
                f"(expected load_steps={actual})")

        for match in EXT_USE.finditer(self.text):
            if match.group(1) not in self.ext:
                self.problems.append(
                    f"{self.rel}:{self._line_of(match.start())}: "
                    f"ExtResource(\"{match.group(1)}\") is never declared")
        for match in SUB_USE.finditer(self.text):
            if match.group(1) not in self.sub:
                self.problems.append(
                    f"{self.rel}:{self._line_of(match.start())}: "
                    f"SubResource(\"{match.group(1)}\") is never declared")

        for resource_id, info in self.ext.items():
            path = info["path"]
            if not path.startswith("res://"):
                continue
            if not (ROOT / path[len("res://"):]).exists():
                self.problems.append(
                    f"{self.rel}:{info['line']}: ext_resource id=\"{resource_id}\" "
                    f"points at {path}, which does not exist")

    def unique_names(self) -> set[str]:
        return {str(info["name"]) for info in self.nodes.values() if info["unique"]}

    def resolve(self, base: str, relative: str) -> bool:
        """Is `relative`, read from a script on node `base`, a real node?"""
        target = relative if base == "." else f"{base}/{relative}"
        return target in self.nodes


def check_script_paths(scene: Scene, scripts: dict[str, str]) -> None:
    """Check $Path and %Unique usage in every script attached to this scene."""
    uniques = scene.unique_names()
    for node_path, info in scene.nodes.items():
        script_id = str(info["script_id"])
        if not script_id or script_id not in scene.ext:
            continue
        script_path = scene.ext[script_id]["path"]
        source = scripts.get(script_path)
        if source is None:
            continue
        for number, line in enumerate(source.splitlines(), 1):
            if '$"' in line or "$'" in line:
                continue  # quoted node paths are legitimate; not worth parsing
            code = strip_code(line)
            for used in DOLLAR_PATH.findall(code):
                if not scene.resolve(node_path, used):
                    scene.problems.append(
                        f"{script_path}:{number}: ${used} does not resolve from "
                        f"node '{node_path}' in {scene.rel}")
            for used in UNIQUE_USE.findall(code):
                if used not in uniques:
                    scene.problems.append(
                        f"{script_path}:{number}: %{used} has no node with "
                        f"unique_name_in_owner = true in {scene.rel}")


def main() -> int:
    scripts = {
        "res://" + str(p.relative_to(ROOT)): p.read_text(encoding="utf-8")
        for p in ROOT.rglob("*.gd")
    }
    scenes = [Scene(p) for p in sorted(ROOT.rglob("*.tscn"))]

    problems: list[str] = []
    seen_uid: dict[str, str] = {}
    for scene in scenes:
        scene.check()
        check_script_paths(scene, scripts)
        problems.extend(scene.problems)
        if scene.uid:
            if scene.uid in seen_uid:
                problems.append(
                    f"{scene.rel}:1: uid {scene.uid} is already used by {seen_uid[scene.uid]}")
            seen_uid[scene.uid] = scene.rel

    nodes = sum(len(scene.nodes) for scene in scenes)
    print(f"checked {len(scenes)} scenes, {nodes} nodes, {len(scripts)} scripts")

    if problems:
        print("\nFAIL")
        for problem in problems:
            print(f" - {problem}")
        return 1

    print("All scenes well-formed; every $ and % path resolves.")
    return 0


if __name__ == "__main__":
    sys.exit(main())
