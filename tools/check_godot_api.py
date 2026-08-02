#!/usr/bin/env python3
"""Catch GDScript that collides with the engine: shadowed native members,
redefined virtuals, and CanvasItem methods called from a Node.

This exists because of a specific, expensive failure. Twelve checkers were
green, every build was green, and three scripts had not parsed for weeks:

  * sfx.gd defined `_get(String) -> AudioStream`. `_get` is Object's virtual
    property accessor with a fixed signature, so the file did not compile —
    and every script that mentions Sfx went down with it.
  * fireball.gd and premium.gd declared `@export var gravity` on an Area2D,
    which already has a native `gravity`.
  * hud.gd called `get_viewport_rect()` while extending CanvasLayer, which is
    a Node and not a CanvasItem.

None of those are visible to a checker that reads source as text and knows
nothing about Godot's class hierarchy. So this one carries a small, curated
slice of that hierarchy — only the classes this project actually extends —
and checks the three collisions above against it.

It is deliberately NOT exhaustive. Godot has hundreds of classes and thousands
of properties; encoding all of them here would be a second, worse copy of the
engine docs that nobody would maintain. What it covers is the shape of mistake
that has actually happened, on the bases this codebase uses. Adding a base
class means adding it to ANCESTRY and NATIVE_MEMBERS below.

Run from the repository root:  python3 tools/check_godot_api.py
"""

from __future__ import annotations

import re
import sys
from pathlib import Path

ROOT = Path(__file__).resolve().parent.parent

# Godot's inheritance, for the bases used here. Each entry lists ancestors
# nearest-first; the class itself is implied.
ANCESTRY = {
    "Object": [],
    "RefCounted": ["Object"],
    "Resource": ["RefCounted", "Object"],
    "Node": ["Object"],
    "CanvasLayer": ["Node", "Object"],
    "CanvasItem": ["Node", "Object"],
    "ParallaxBackground": ["CanvasLayer", "Node", "Object"],
    "Node2D": ["CanvasItem", "Node", "Object"],
    "Control": ["CanvasItem", "Node", "Object"],
    "Label": ["Control", "CanvasItem", "Node", "Object"],
    "Button": ["BaseButton", "Control", "CanvasItem", "Node", "Object"],
    "BaseButton": ["Control", "CanvasItem", "Node", "Object"],
    "Range": ["Control", "CanvasItem", "Node", "Object"],
    "ProgressBar": ["Range", "Control", "CanvasItem", "Node", "Object"],
    "PanelContainer": ["Container", "Control", "CanvasItem", "Node", "Object"],
    "Container": ["Control", "CanvasItem", "Node", "Object"],
    "Polygon2D": ["Node2D", "CanvasItem", "Node", "Object"],
    "Marker2D": ["Node2D", "CanvasItem", "Node", "Object"],
    "Camera2D": ["Node2D", "CanvasItem", "Node", "Object"],
    "CollisionObject2D": ["Node2D", "CanvasItem", "Node", "Object"],
    "Area2D": ["CollisionObject2D", "Node2D", "CanvasItem", "Node", "Object"],
    "PhysicsBody2D": ["CollisionObject2D", "Node2D", "CanvasItem", "Node", "Object"],
    "CharacterBody2D": ["PhysicsBody2D", "CollisionObject2D", "Node2D",
                        "CanvasItem", "Node", "Object"],
    "StaticBody2D": ["PhysicsBody2D", "CollisionObject2D", "Node2D",
                     "CanvasItem", "Node", "Object"],
    "AnimatableBody2D": ["StaticBody2D", "PhysicsBody2D", "CollisionObject2D",
                         "Node2D", "CanvasItem", "Node", "Object"],
    "RigidBody2D": ["PhysicsBody2D", "CollisionObject2D", "Node2D",
                    "CanvasItem", "Node", "Object"],
    "AudioStreamPlayer": ["Node", "Object"],
    "Timer": ["Node", "Object"],
    "VisibleOnScreenNotifier2D": ["VisibleOnScreenEnabler2D", "Node2D",
                                  "CanvasItem", "Node", "Object"],
}

# Native properties. Declaring `var x` where an ancestor already has `x` is a
# parse error, not a shadow: "Member redefined (original in native class ...)".
NATIVE_MEMBERS = {
    "Node": {"name", "owner", "scene_file_path", "process_mode", "process_priority",
             "process_physics_priority", "unique_name_in_owner", "editor_description",
             "multiplayer", "process_thread_group"},
    "CanvasItem": {"visible", "modulate", "self_modulate", "show_behind_parent",
                   "top_level", "clip_children", "light_mask", "visibility_layer",
                   "z_index", "z_as_relative", "y_sort_enabled", "texture_filter",
                   "texture_repeat", "material", "use_parent_material"},
    "CanvasLayer": {"layer", "offset", "rotation", "scale", "transform",
                    "custom_viewport", "follow_viewport_enabled"},
    "Node2D": {"position", "rotation", "rotation_degrees", "scale", "skew",
               "transform", "global_position", "global_rotation", "global_scale",
               "global_transform", "global_skew", "global_rotation_degrees"},
    "Control": {"size", "custom_minimum_size", "layout_direction", "layout_mode",
                "anchor_left", "anchor_top", "anchor_right", "anchor_bottom",
                "offset_left", "offset_top", "offset_right", "offset_bottom",
                "grow_horizontal", "grow_vertical", "pivot_offset",
                "size_flags_horizontal", "size_flags_vertical", "size_flags_stretch_ratio",
                "focus_mode", "focus_neighbor_left", "mouse_filter",
                "mouse_default_cursor_shape", "mouse_force_pass_scroll_events",
                "theme", "theme_type_variation", "tooltip_text", "clip_contents",
                "auto_translate", "localize_numeral_system"},
    "BaseButton": {"disabled", "toggle_mode", "button_pressed", "action_mode",
                   "button_mask", "keep_pressed_outside", "shortcut",
                   "shortcut_feedback", "shortcut_in_tooltip", "button_group"},
    "Label": {"text", "label_settings", "horizontal_alignment", "vertical_alignment",
              "autowrap_mode", "clip_text", "text_overrun_behavior", "uppercase",
              "lines_skipped", "max_lines_visible", "visible_characters",
              "visible_ratio", "justification_flags"},
    "Range": {"min_value", "max_value", "step", "page", "value", "ratio",
              "exp_edit", "rounded", "allow_greater", "allow_lesser"},
    "ProgressBar": {"fill_mode", "show_percentage", "indeterminate", "editor_preview_indeterminate"},
    "Polygon2D": {"polygon", "uv", "color", "vertex_colors", "polygons", "bones",
                  "internal_vertex_count", "antialiased", "texture",
                  "texture_offset", "texture_scale", "texture_rotation", "offset",
                  "invert_enabled", "invert_border"},
    "Camera2D": {"anchor_mode", "ignore_rotation", "enabled", "zoom", "custom_viewport",
                 "process_callback", "limit_left", "limit_top", "limit_right",
                 "limit_bottom", "limit_smoothed", "position_smoothing_enabled",
                 "position_smoothing_speed", "rotation_smoothing_enabled",
                 "rotation_smoothing_speed", "drag_horizontal_enabled",
                 "drag_vertical_enabled", "editor_draw_screen", "editor_draw_limits",
                 "editor_draw_drag_margin", "offset"},
    "CollisionObject2D": {"disable_mode", "collision_layer", "collision_mask",
                          "collision_priority", "input_pickable"},
    "Area2D": {"monitoring", "monitorable", "priority", "gravity_space_override",
               "gravity_point", "gravity_point_center", "gravity_point_unit_distance",
               "gravity_direction", "gravity", "linear_damp_space_override",
               "linear_damp", "angular_damp_space_override", "angular_damp",
               "audio_bus_override", "audio_bus_name"},
    "PhysicsBody2D": {"constant_linear_velocity", "constant_angular_velocity"},
    "CharacterBody2D": {"motion_mode", "up_direction", "velocity", "slide_on_ceiling",
                        "max_slides", "wall_min_slide_angle", "floor_stop_on_slope",
                        "floor_constant_speed", "floor_block_on_wall", "floor_max_angle",
                        "floor_snap_length", "platform_on_leave", "platform_floor_layers",
                        "platform_wall_layers", "safe_margin"},
    "RigidBody2D": {"mass", "inertia", "center_of_mass", "physics_material_override",
                    "gravity_scale", "linear_velocity", "angular_velocity",
                    "linear_damp", "angular_damp", "sleeping", "can_sleep",
                    "lock_rotation", "freeze", "freeze_mode", "continuous_cd",
                    "contact_monitor", "max_contacts_reported"},
    "AudioStreamPlayer": {"stream", "volume_db", "volume_linear", "pitch_scale",
                          "playing", "autoplay", "stream_paused", "mix_target",
                          "max_polyphony", "bus", "playback_type"},
    "Timer": {"process_callback", "wait_time", "one_shot", "autostart", "paused",
              "time_left", "ignore_time_scale"},
    "VisibleOnScreenNotifier2D": {"rect"},
    "ParallaxBackground": {"scroll_offset", "scroll_base_offset", "scroll_base_scale",
                           "scroll_limit_begin", "scroll_limit_end",
                           "scroll_ignore_camera_zoom"},
}

# Virtuals whose signature the engine fixes. Redefining one with a different
# parameter count is a parse error, and the message names the parent signature
# rather than your file, which makes it a genuinely confusing one to chase.
# (parameter types, return type). A parameter written without a type is not
# checked; a mismatch on one that has a type is. Arity alone is not enough —
# sfx.gd's `_get(sound: String) -> AudioStream` had exactly the one argument
# the virtual takes, and still brought down half the project.
FIXED_VIRTUALS = {
    "_get": (["StringName"], "Variant"),
    "_set": (["StringName", "Variant"], "bool"),
    "_get_property_list": ([], "Array"),
    "_property_can_revert": (["StringName"], "bool"),
    "_property_get_revert": (["StringName"], "Variant"),
    "_validate_property": (["Dictionary"], "void"),
    "_to_string": ([], "String"),
    "_notification": (["int"], "void"),
    "_ready": ([], "void"),
    "_enter_tree": ([], "void"),
    "_exit_tree": ([], "void"),
    "_process": (["float"], "void"),
    "_physics_process": (["float"], "void"),
    "_input": (["InputEvent"], "void"),
    "_unhandled_input": (["InputEvent"], "void"),
    "_unhandled_key_input": (["InputEvent"], "void"),
    "_shortcut_input": (["InputEvent"], "void"),
    "_gui_input": (["InputEvent"], "void"),
    "_draw": ([], "void"),
    "_get_configuration_warnings": ([], "PackedStringArray"),
}

# Methods that live on CanvasItem, not Node. Calling one from a CanvasLayer or
# a plain Node script is a parse error.
CANVAS_ITEM_ONLY = {
    "get_viewport_rect", "queue_redraw", "get_global_mouse_position",
    "get_local_mouse_position", "get_canvas_transform", "get_global_transform",
    "get_viewport_transform", "draw_line", "draw_circle", "draw_rect",
    "draw_string", "draw_arc", "draw_polygon", "draw_texture", "draw_colored_polygon",
    "get_screen_transform", "make_canvas_position_local",
}

# Column zero only. A local `var offset` inside a function shadows nothing —
# GDScript warns about it at most. Only a class-level declaration collides with
# a native member.
DECL_VAR = re.compile(r"^(?:@\w+(?:\([^)]*\))?\s+)*var\s+(\w+)", re.MULTILINE)
DECL_FUNC = re.compile(r"^func\s+(\w+)\s*\((.*?)\)\s*(?:->\s*(\w+))?\s*:", re.MULTILINE)
EXTENDS = re.compile(r'^extends\s+"?([\w/:.]+)"?', re.MULTILINE)
CLASS_NAME = re.compile(r"^class_name\s+(\w+)", re.MULTILINE)


def strip_code(text: str) -> str:
    """Blank comments and string bodies, preserving line structure. Without
    this, a comment that names get_viewport_rect() to explain why it is *not*
    used reads as a call to it."""
    lines = []
    for line in text.split("\n"):
        out: list[str] = []
        quote = ""
        index = 0
        while index < len(line):
            char = line[index]
            if quote:
                if char == "\\":
                    index += 2
                    continue
                if char == quote:
                    quote = ""
                index += 1
                continue
            if char == "#":
                break
            if char in "\"'":
                quote = char
                out.append('""')
                index += 1
                continue
            out.append(char)
            index += 1
        lines.append("".join(out))
    return "\n".join(lines)


def split_args(text: str) -> list[str]:
    args, depth, current = [], 0, ""
    for char in text:
        if char in "([{":
            depth += 1
        elif char in ")]}":
            depth -= 1
        if char == "," and depth == 0:
            args.append(current.strip())
            current = ""
            continue
        current += char
    if current.strip():
        args.append(current.strip())
    return [a for a in args if a]


def main() -> int:
    # Inheritance is read from the raw text: `extends "res://..."` is a string
    # literal, and strip_code would blank the very path we need.
    raw = {("res://" + str(p.relative_to(ROOT))): p.read_text(encoding="utf-8")
           for p in sorted(ROOT.rglob("*.gd"))}
    sources = {path: strip_code(text) for path, text in raw.items()}
    by_class = {}
    for path, text in raw.items():
        found = CLASS_NAME.search(text)
        if found:
            by_class[found.group(1)] = path

    def engine_base(path: str, seen: set[str] | None = None) -> str | None:
        """Walk `extends` until it lands on a Godot class we know."""
        seen = seen or set()
        if path in seen or path not in raw:
            return None
        seen.add(path)
        found = EXTENDS.search(raw[path])
        if found is None:
            return None
        target = found.group(1)
        if target in ANCESTRY:
            return target
        if target in by_class:
            return engine_base(by_class[target], seen)
        if target.startswith("res://"):
            return engine_base(target, seen)
        return None

    problems: list[str] = []
    resolved = 0
    unknown_bases: set[str] = set()

    for path, text in sources.items():
        rel = path[len("res://"):]
        base = engine_base(path)
        if base is None:
            found = EXTENDS.search(raw[path])
            if found and found.group(1) not in ANCESTRY:
                unknown_bases.add(found.group(1))
            continue
        resolved += 1
        chain = [base] + ANCESTRY[base]
        native: set[str] = set()
        for ancestor in chain:
            native |= NATIVE_MEMBERS.get(ancestor, set())

        for match in DECL_VAR.finditer(text):
            name = match.group(1)
            if name in native:
                owner = next(a for a in chain if name in NATIVE_MEMBERS.get(a, set()))
                line = text.count("\n", 0, match.start()) + 1
                problems.append(
                    f"{rel}:{line}: `var {name}` redefines a native member of "
                    f"{owner} (this script extends {base}) — Godot rejects the "
                    f"whole file")

        for match in DECL_FUNC.finditer(text):
            name, params, returns = match.group(1), match.group(2), match.group(3)
            if name not in FIXED_VIRTUALS:
                continue
            want_params, want_return = FIXED_VIRTUALS[name]
            args = split_args(params)
            line = text.count("\n", 0, match.start()) + 1
            complaint = ""
            if len(args) != len(want_params):
                complaint = (f"takes {len(want_params)} argument(s), not {len(args)}")
            else:
                for arg, want in zip(args, want_params):
                    if ":" not in arg:
                        continue                    # untyped: nothing to compare
                    got = arg.split(":", 1)[1].split("=")[0].strip()
                    if got != want and want != "Variant":
                        complaint = (f"argument `{arg.split(':')[0].strip()}` is "
                                     f"{want}, not {got}")
                        break
            if not complaint and returns and want_return not in ("Variant", returns):
                complaint = f"returns {want_return}, not {returns}"
            if complaint:
                problems.append(
                    f"{rel}:{line}: `{name}()` is an engine virtual and {complaint} "
                    f"— redefining it with another signature stops this file, and "
                    f"everything that references it, from compiling")

        # CanvasItem-only calls from a base that is not one.
        if "CanvasItem" not in chain and base != "CanvasItem":
            for method in CANVAS_ITEM_ONLY:
                for match in re.finditer(rf"(?<![\w.]){re.escape(method)}\s*\(", text):
                    line = text.count("\n", 0, match.start()) + 1
                    problems.append(
                        f"{rel}:{line}: {method}() is a CanvasItem method, and this "
                        f"script extends {base}, which is not one")

    print(f"  resolved an engine base for {resolved} of {len(sources)} scripts")
    if unknown_bases:
        print("  bases not in the table (unchecked): " + ", ".join(sorted(unknown_bases)))

    if problems:
        print("\nFAIL")
        for problem in sorted(set(problems)):
            print(f" - {problem}")
        return 1

    print("\nNo native members shadowed, no engine virtuals redefined.")
    return 0


if __name__ == "__main__":
    sys.exit(main())
