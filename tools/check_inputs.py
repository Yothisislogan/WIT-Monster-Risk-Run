#!/usr/bin/env python3
"""Verify every input action the game references actually exists.

Godot fails an unknown action name at runtime with a console error and an
input that simply never fires -- on a phone that looks like a dead button
rather than a bug. Scenes are the worst case: `action = &"cycle_abilty"` on
a virtual button is a silent no-op with no stack trace to follow.

This checks three reference sites against the [input] block of
project.godot (plus Godot's built-in ui_* actions):

  * scripts   Input.is_action_*("x"), Input.action_press("x"),
              Input.get_axis("a", "b"), event.is_action_pressed("x")
  * scenes    action = &"x" / action = "x"
  * unused    actions declared in project.godot that nothing references

Run from the repository root:  python3 tools/check_inputs.py
"""

from __future__ import annotations

import re
import sys
from pathlib import Path

ROOT = Path(__file__).resolve().parent.parent

# Godot declares these itself; they are legal without appearing in the
# project's own [input] block.
BUILTIN = {
    "ui_accept", "ui_select", "ui_cancel", "ui_focus_next", "ui_focus_prev",
    "ui_left", "ui_right", "ui_up", "ui_down", "ui_page_up", "ui_page_down",
    "ui_home", "ui_end", "ui_cut", "ui_copy", "ui_paste", "ui_undo",
    "ui_redo", "ui_text_completion_query", "ui_text_newline",
    "ui_text_newline_blank", "ui_menu",
}

# Input.is_action_pressed("jump"), .is_action_just_released("jump"), ...
SCRIPT_SINGLE = re.compile(
    r'(?:Input|event|_event)\.(?:is_action(?:_just)?_(?:pressed|released)'
    r'|action_press|action_release)\(\s*"([a-z_0-9]+)"'
)
# Input.get_axis("move_left", "move_right")
SCRIPT_AXIS = re.compile(
    r'get_(?:axis|vector)\(\s*"([a-z_0-9]+)"\s*,\s*"([a-z_0-9]+)"'
    r'(?:\s*,\s*"([a-z_0-9]+)"\s*,\s*"([a-z_0-9]+)")?'
)
# action = &"cycle_ability"  (and the unquoted-StringName-free variant)
SCENE_ACTION = re.compile(r'^\s*action\s*=\s*&?"([a-z_0-9]+)"', re.MULTILINE)


def declared_actions() -> set[str]:
    """Action names in the [input] section of project.godot."""
    text = (ROOT / "project.godot").read_text(encoding="utf-8")
    match = re.search(r"^\[input\]$(.*?)(?=^\[|\Z)", text, re.MULTILINE | re.DOTALL)
    if not match:
        return set()
    # Only line-initial `name={` starts an action; the event arrays that
    # follow are indented or bracketed.
    return set(re.findall(r"^([a-z_0-9]+)=\{", match.group(1), re.MULTILINE))


def references() -> list[tuple[str, str, int]]:
    """(action, file, line) for every action reference in scripts and scenes."""
    found: list[tuple[str, str, int]] = []
    for path in sorted(ROOT.rglob("*.gd")):
        rel = str(path.relative_to(ROOT))
        for number, line in enumerate(path.read_text(encoding="utf-8").splitlines(), 1):
            for name in SCRIPT_SINGLE.findall(line):
                found.append((name, rel, number))
            for group in SCRIPT_AXIS.findall(line):
                for name in group:
                    if name:
                        found.append((name, rel, number))
    for path in sorted(ROOT.rglob("*.tscn")):
        rel = str(path.relative_to(ROOT))
        text = path.read_text(encoding="utf-8")
        for match in SCENE_ACTION.finditer(text):
            line = text.count("\n", 0, match.start()) + 1
            found.append((match.group(1), rel, line))
    return found


def main() -> int:
    declared = declared_actions()
    if not declared:
        print("FAIL\n - project.godot has no [input] section")
        return 1

    refs = references()
    problems = [
        f"{path}:{line}: input action '{name}' is not declared in project.godot"
        for name, path, line in refs
        if name not in declared and name not in BUILTIN
    ]

    print(f"checked {len(declared)} declared actions, {len(refs)} references")

    if problems:
        print("\nFAIL")
        for problem in problems:
            print(f" - {problem}")
        return 1

    # Not a failure: an action can legitimately exist for a platform this
    # build does not exercise. Worth saying out loud all the same.
    unused = sorted(declared - {name for name, _, _ in refs})
    if unused:
        print("note: declared but never referenced: " + ", ".join(unused))

    print("All input actions resolve.")
    return 0


if __name__ == "__main__":
    sys.exit(main())
