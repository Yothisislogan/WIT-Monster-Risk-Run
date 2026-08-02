#!/usr/bin/env python3
"""Static reference check for GDScript.

Godot only reports a missing autoload method or a bad class name at runtime,
often deep in a scene. This walks every script and verifies that:
  - every `Autoload.member` reference names something the autoload declares
  - every `ClassName.member` reference names something that class declares
  - scripts referenced by scenes exist, and vice versa

It is deliberately conservative: it only flags a reference when it can see
the whole declaration list for that target.
"""
import re, sys
from pathlib import Path

ROOT = Path(__file__).resolve().parent.parent

DECL = re.compile(
    r'^\s*(?:@export\s+)?(?:static\s+)?(?:func|var|const|signal|enum)\s+([A-Za-z_]\w*)', re.M)
CLASS_NAME = re.compile(r'^class_name\s+([A-Za-z_]\w*)', re.M)
# Members inherited from Node/Object that autoloads legitimately expose.
BUILTIN = {
    "new", "call", "call_deferred", "set", "get", "free", "queue_free", "connect",
    "disconnect", "emit", "emit_signal", "has_method", "has_signal", "name",
    "get_tree", "get_parent", "add_child", "process_mode", "set_deferred",
    "is_connected", "get_node", "duplicate", "resource_path", "instantiate",
}


def declarations(path):
    text = path.read_text()
    names = set(DECL.findall(text))
    # enum bodies expose their entries as Class.ENTRY
    for body in re.findall(r'enum\s+\w*\s*\{([^}]*)\}', text):
        for entry in body.split(","):
            entry = entry.split("=")[0].strip()
            if entry:
                names.add(entry)
    return names


def main():
    problems = []

    # --- autoloads from project.godot ------------------------------------
    proj = (ROOT / "project.godot").read_text()
    autoload_block = re.search(r'\[autoload\]\n(.*?)(?:\n\[|\Z)', proj, re.S)
    autoloads = {}
    if autoload_block:
        for name, res in re.findall(r'^(\w+)="\*?(res://[^"]+)"', autoload_block.group(1), re.M):
            path = ROOT / res.replace("res://", "")
            if not path.exists():
                problems.append(f"project.godot: autoload {name} -> missing {res}")
                continue
            autoloads[name] = declarations(path)

    # --- class_name declarations ------------------------------------------
    classes = {}
    for gd in ROOT.rglob("*.gd"):
        m = CLASS_NAME.search(gd.read_text())
        if m:
            classes[m.group(1)] = declarations(gd)

    targets = {}
    targets.update(classes)
    targets.update(autoloads)   # autoloads win on name collisions

    # --- check every referenced member -------------------------------------
    for gd in sorted(ROOT.rglob("*.gd")):
        text = gd.read_text()
        own = declarations(gd) | classes.get(
            (CLASS_NAME.search(text).group(1) if CLASS_NAME.search(text) else ""), set())
        for line_no, line in enumerate(text.splitlines(), 1):
            code = re.sub(r'#.*', '', line)
            code = re.sub(r'"[^"]*"', '""', code)
            for target, member in re.findall(r'\b([A-Z][A-Za-z0-9_]*)\.([a-zA-Z_]\w*)', code):
                if target not in targets:
                    continue
                if member in BUILTIN or member in targets[target]:
                    continue
                # a script may reference its own inherited members
                if target in classes and member in own:
                    continue
                problems.append(
                    f"{gd.relative_to(ROOT)}:{line_no}: {target}.{member} is not declared in {target}")

    # --- scripts referenced by scenes exist --------------------------------
    for tscn in ROOT.rglob("*.tscn"):
        for res in re.findall(r'\[ext_resource type="Script" path="([^"]+)"', tscn.read_text()):
            if not (ROOT / res.replace("res://", "")).exists():
                problems.append(f"{tscn.relative_to(ROOT)}: missing script {res}")

    print(f"checked {len(autoloads)} autoloads, {len(classes)} classes")
    if problems:
        print("\nFAIL")
        for p in sorted(set(problems)):
            print(" -", p)
        sys.exit(1)
    print("All autoload and class references resolve.")


if __name__ == "__main__":
    main()
