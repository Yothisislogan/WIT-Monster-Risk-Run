#!/usr/bin/env python3
"""Prove the title screen composes: nothing overlaps, nothing leaves the frame.

The title screen is now a storm over Blaze Borough with a five-times-life-size
Monster standing in it, a wordmark that flies in, and the menu column beside
both. None of that is in the .tscn — it is built in code, at positions given as
constants, and there is no Godot here to open the scene and look at it.

The failure this is written against is not a crash. It is the Monster's horn
tip landing on the M of MONSTER, or the fourth menu button sliding under the
lifetime-record line: things that would ship, look wrong, and never be caught
by a parse check. So this measures the boxes and asserts they are disjoint.

Nothing here restates a number from the game. The polygons, the offsets, the
animation amplitudes and the layout rectangles are all read out of
scripts/ui/title_*.gd and scenes/title.tscn; move the Monster and this check
moves with it. What IS restated is the *structure* of the Monster's build
function — which polygon is placed where, and which are mirrored — because the
alternative is parsing GDScript. That restatement is guarded: every
PackedVector2Array constant in title_monster.gd must appear in PARTS, so
adding a limb without telling this file fails rather than going unmeasured.

Run from the repository root:  python3 tools/check_title.py
"""

from __future__ import annotations

import math
import re
import sys
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parent))
from check_text_fit import AVG_GLYPH, UPPER_GLYPH, line_height  # noqa: E402

ROOT = Path(__file__).resolve().parent.parent

## The design viewport, from project.godot.
DESIGN = (1280.0, 720.0)
## The widest phone the backdrop has to cover. A 20:9 landscape display with
## stretch aspect "expand" shows 720 * 20/9 = 1600px of width, i.e. 160px past
## each side of the design box.
WIDEST_ASPECT = 20.0 / 9.0

## Which Monster polygons go where. Each entry is
##   (constant, offset constant or None, mirrored, repeat count, spacing const)
## and is checked against the constants in the script, never against literals.
PARTS = [
    ("BODY", None, False, 1, None),
    ("BELLY", None, False, 1, None),
    ("FOOT", "FOOT_OFFSET", True, 1, None),
    ("CLAW_TOOTH", "FOOT_OFFSET", True, "CLAW_TOES", "CLAW_SPACING"),
    ("ARM", "ARM_OFFSET", True, 1, None),
    ("HORN", "HORN_OFFSET", True, 1, None),
    ("BROW", "BROW_OFFSET", True, 1, None),
    ("TAIL", "TAIL_OFFSET", False, 1, None),
    ("MOUTH", "MOUTH_OFFSET", False, 1, None),
    ("TOOTH_SHAPE", "TOOTH_OFFSET", False, "TOOTH_COUNT", "TOOTH_SPACING"),
]


def read(path: str) -> str:
    return (ROOT / path).read_text(encoding="utf-8")


# --- reading numbers back out of GDScript ------------------------------------

def scalar(source: str, name: str) -> float:
    found = re.search(rf"^const {name} :?= ([-\d.]+)", source, re.MULTILINE)
    if found is None:
        raise SystemExit(f"no const {name} found")
    return float(found.group(1))


def vec2(source: str, name: str) -> tuple[float, float]:
    found = re.search(
        rf"^const {name} :?= Vector2\(([-\d.]+), *([-\d.]+)\)", source, re.MULTILINE)
    if found is None:
        raise SystemExit(f"no const {name} := Vector2(...) found")
    return (float(found.group(1)), float(found.group(2)))


def rect2(source: str, name: str) -> tuple[float, float, float, float]:
    found = re.search(
        rf"^const {name} :?= Rect2\(([-\d.]+), *([-\d.]+), *([-\d.]+), *([-\d.]+)\)",
        source, re.MULTILINE)
    if found is None:
        raise SystemExit(f"no const {name} := Rect2(...) found")
    x, y, w, h = (float(g) for g in found.groups())
    return (x, y, x + w, y + h)


def polygon(source: str, name: str) -> list[tuple[float, float]]:
    found = re.search(
        rf"^const {name}: Array\[Vector2\] = \[(.*?)\n\]",
        source, re.MULTILINE | re.DOTALL)
    if found is None:
        raise SystemExit(f"no const {name}: Array[Vector2] = [...] found")
    return [(float(x), float(y)) for x, y
            in re.findall(r"Vector2\(([-\d.]+), *([-\d.]+)\)", found.group(1))]


def polygon_names(source: str) -> set[str]:
    return set(re.findall(r"^const (\w+): Array\[Vector2\] = \[",
                          source, re.MULTILINE))


# --- reading boxes back out of a .tscn ---------------------------------------

def node_box(scene: str, name: str, parent: tuple[float, float]) -> tuple:
    """Absolute (left, top, right, bottom) of a Control, from its anchors and
    offsets against a parent of the given size."""
    block = re.search(rf'\[node name="{name}"[^\]]*\](.*?)(?=\n\[node |\Z)',
                      read(scene), re.DOTALL)
    if block is None:
        raise SystemExit(f"{scene} has no node named {name}")
    body = block.group(1)

    def value(key: str) -> float:
        found = re.search(rf"^{key} = ([-\d.]+)", body, re.MULTILINE)
        return float(found.group(1)) if found else 0.0

    return (value("anchor_left") * parent[0] + value("offset_left"),
            value("anchor_top") * parent[1] + value("offset_top"),
            value("anchor_right") * parent[0] + value("offset_right"),
            value("anchor_bottom") * parent[1] + value("offset_bottom"))


def overlap(a: tuple, b: tuple) -> bool:
    return a[0] < b[2] and b[0] < a[2] and a[1] < b[3] and b[1] < a[3]


# --- the Monster --------------------------------------------------------------

def ellipse(rx: float, ry: float, segments: int = 24) -> list[tuple[float, float]]:
    return [(math.cos(math.tau * i / segments) * rx,
             math.sin(math.tau * i / segments) * ry) for i in range(segments)]


def monster_points(src: str) -> list[tuple[float, float]]:
    """Every point the Monster draws, in local space, before the idle animation
    but with every *pose* extreme included: the mouth at full open, the pupils
    at the end of their drift, the tail at the end of its swing."""
    points: list[tuple[float, float]] = []

    def place(shape, ox: float, oy: float, sx: float = 1.0, sy: float = 1.0) -> None:
        points.extend((ox + x * sx, oy + y * sy) for x, y in shape)

    body = polygon(src, "BODY")
    place(body, 0.0, 0.0)
    place(body, *vec2(src, "RIM_OFFSET"))          # the lit silhouette copy
    place(polygon(src, "BELLY"), 0.0, 0.0)

    for entry in PARTS:
        name, offset_name, mirrored, repeat, spacing_name = entry
        if name in ("BODY", "BELLY"):
            continue
        shape = polygon(src, name)
        origin = vec2(src, offset_name) if offset_name else (0.0, 0.0)
        count = int(scalar(src, repeat)) if isinstance(repeat, str) else repeat
        spacing = scalar(src, spacing_name) if spacing_name else 0.0
        # A repeated part is laid out around its offset for the claws (toe - 1)
        # and forward from it for the teeth; taking both extremes covers each.
        spread = [0.0] if count == 1 else [
            i * spacing for i in range(count)] + [
            (i - 1) * spacing for i in range(count)]
        for side in ((-1.0, 1.0) if mirrored else (1.0,)):
            for step in spread:
                place(shape, origin[0] * side + step, origin[1], sx=side)

    # The mouth is scaled open every frame, so it is measured at its widest.
    place(polygon(src, "MOUTH"), *vec2(src, "MOUTH_OFFSET"),
          sx=1.0 + scalar(src, "STARTLE_MOUTH_WIDEN"),
          sy=scalar(src, "MOUTH_OPEN_MAX"))

    eye = vec2(src, "EYE_OFFSET")
    eye_r = scalar(src, "EYE_RADIUS")
    pupil_r = scalar(src, "PUPIL_RADIUS")
    travel = scalar(src, "PUPIL_TRAVEL")
    lid_margin = scalar(src, "LID_MARGIN")
    lid_height = eye_r * scalar(src, "LID_HEIGHT_FACTOR")
    for side in (-1.0, 1.0):
        place(ellipse(eye_r, eye_r * scalar(src, "EYE_SQUASH")), eye[0] * side, eye[1])
        for drift_x in (-travel, travel):
            for drift_y in (-travel, travel):
                place(ellipse(pupil_r, pupil_r),
                      eye[0] * side + drift_x, eye[1] + drift_y)
        place([(-eye_r - lid_margin, 0.0), (eye_r + lid_margin, 0.0),
               (eye_r + lid_margin, lid_height), (-eye_r - lid_margin, lid_height)],
              eye[0] * side, eye[1] - eye_r)

    # The tail hangs off a node that rotates further than the body sways, so
    # sweep its swing rather than trusting the rest pose.
    tail_origin = vec2(src, "TAIL_OFFSET")
    swing = math.radians(scalar(src, "SWAY_DEGREES") * scalar(src, "TAIL_SWAY_FACTOR"))
    for angle in (-swing, 0.0, swing):
        for x, y in polygon(src, "TAIL"):
            points.append((tail_origin[0] + x * math.cos(angle) - y * math.sin(angle),
                           tail_origin[1] + x * math.sin(angle) + y * math.cos(angle)))
    return points


def animated_box(src: str, points: list[tuple[float, float]]) -> tuple:
    """The screen-space box the Monster can occupy across its whole idle: the
    breath scaling, the sway rotation, the bob and the startle lift, composed
    the same way _process composes them."""
    breath = scalar(src, "BREATH")
    squash = scalar(src, "BREATH_SQUASH_RATIO")
    swell = scalar(src, "STARTLE_SWELL")
    startle_squash = scalar(src, "STARTLE_SQUASH")
    sway = math.radians(scalar(src, "SWAY_DEGREES"))
    lift = scalar(src, "IDLE_BOB") + scalar(src, "STARTLE_LIFT")
    art_scale = scalar(src, "ART_SCALE")
    home = vec2(src, "HOME")

    scales_x = (1.0 - breath, 1.0 + breath + swell)
    scales_y = (1.0 - breath * squash, 1.0 + breath * squash + startle_squash)
    # The bob only ever lifts, so the downward reach is the unlifted pose.
    lifts = (-lift, 0.0)

    left = top = math.inf
    right = bottom = -math.inf
    for sx in scales_x:
        for sy in scales_y:
            for angle in (-sway, 0.0, sway):
                cos_a, sin_a = math.cos(angle), math.sin(angle)
                for x, y in points:
                    px, py = x * sx, y * sy
                    rx = px * cos_a - py * sin_a
                    ry = px * sin_a + py * cos_a
                    for dy in lifts:
                        left = min(left, rx)
                        right = max(right, rx)
                        top = min(top, ry + dy)
                        bottom = max(bottom, ry + dy)
    return (home[0] + left * art_scale, home[1] + top * art_scale,
            home[0] + right * art_scale, home[1] + bottom * art_scale)


def text_width(text: str, size: int) -> float:
    glyph = UPPER_GLYPH if text == text.upper() else AVG_GLYPH
    return len(text) * glyph * size


def main() -> int:
    problems: list[str] = []
    rows: list[str] = []

    monster_src = read("scripts/ui/title_monster.gd")
    logo_src = read("scripts/ui/title_logo.gd")
    screen_src = read("scripts/ui/title_screen.gd")
    splash_src = read("scripts/ui/title_splash.gd")
    scene = "scenes/title.tscn"

    # --- the Stage is the design box ----------------------------------------
    stage = node_box(scene, "Stage", DESIGN)
    rows.append("  stage: %.0f,%.0f to %.0f,%.0f" % stage)
    if (stage[0], stage[1], stage[2], stage[3]) != (0.0, 0.0, DESIGN[0], DESIGN[1]):
        problems.append(
            "the Stage is %.0fx%.0f at (%.0f,%.0f), not the %.0fx%.0f design box — "
            "every position on this screen is a design coordinate and assumes it is"
            % (stage[2] - stage[0], stage[3] - stage[1], stage[0], stage[1],
               DESIGN[0], DESIGN[1]))

    # --- every polygon is accounted for --------------------------------------
    declared = polygon_names(monster_src)
    covered = {entry[0] for entry in PARTS}
    missing = declared - covered
    if missing:
        problems.append(
            "title_monster.gd declares %s, which PARTS in this file does not place. "
            "Add it there or the Monster is being measured without it"
            % ", ".join(sorted(missing)))
    stale = covered - declared
    if stale:
        problems.append(
            "PARTS names %s, which title_monster.gd no longer declares"
            % ", ".join(sorted(stale)))

    # --- the art fits the box it claims to fit -------------------------------
    points = monster_points(monster_src)
    art = (min(x for x, _ in points), min(y for _, y in points),
           max(x for x, _ in points), max(y for _, y in points))
    claimed = rect2(monster_src, "LOCAL_BOUNDS")
    rows.append("  monster art: %.0f,%.0f to %.0f,%.0f (LOCAL_BOUNDS says "
                "%.0f,%.0f to %.0f,%.0f)" % (art + claimed))
    if (art[0] < claimed[0] or art[1] < claimed[1]
            or art[2] > claimed[2] or art[3] > claimed[3]):
        problems.append(
            "the Monster's polygons reach %.0f,%.0f..%.0f,%.0f but LOCAL_BOUNDS "
            "claims %.0f,%.0f..%.0f,%.0f — the layout is arranged around the "
            "claim, so the art is now somewhere the layout does not know about"
            % (art + claimed))
    slack = max(claimed[2] - art[2], art[0] - claimed[0],
                claimed[3] - art[3], art[1] - claimed[1])
    if slack > 40.0:
        problems.append(
            "LOCAL_BOUNDS is %.0fpx larger than the art on one side. It is meant "
            "to be the art's box; that much slack means the layout is reserving "
            "space for nothing" % slack)

    # --- the composed layout --------------------------------------------------
    monster = animated_box(monster_src, points)
    logo_origin = vec2(logo_src, "ORIGIN")
    logo = (logo_origin[0], logo_origin[1],
            logo_origin[0] + scalar(logo_src, "WIDTH"),
            logo_origin[1] + scalar(logo_src, "BOX_HEIGHT"))
    menu = node_box(scene, "Menu", DESIGN)
    record = node_box(scene, "RecordLabel", DESIGN)

    boxes = {"monster": monster, "wordmark": logo, "menu": menu, "record line": record}
    for label, box in boxes.items():
        rows.append("  %-12s %.0f,%.0f to %.0f,%.0f" % ((label,) + box))

    names = list(boxes)
    for i in range(len(names)):
        for j in range(i + 1, len(names)):
            if overlap(boxes[names[i]], boxes[names[j]]):
                problems.append(
                    "the %s (%.0f,%.0f..%.0f,%.0f) overlaps the %s "
                    "(%.0f,%.0f..%.0f,%.0f)"
                    % ((names[i],) + boxes[names[i]] + (names[j],) + boxes[names[j]]))

    for label, box in boxes.items():
        if box[0] < 0.0 or box[1] < 0.0 or box[2] > DESIGN[0] or box[3] > DESIGN[1]:
            problems.append(
                "the %s reaches %.0f,%.0f..%.0f,%.0f, outside the %.0fx%.0f frame"
                % ((label,) + box + DESIGN))

    # --- the menu holds every entry it can show ------------------------------
    button = vec2(screen_src, "MENU_BUTTON_SIZE")
    entries = int(scalar(screen_src, "MENU_MAX_ENTRIES"))
    separation = float(re.search(
        r'\[node name="Menu".*?theme_override_constants/separation = (\d+)',
        read(scene), re.DOTALL).group(1))
    needed = entries * button[1] + (entries - 1) * separation
    rows.append("  menu: %d entries of %.0fpx + %.0fpx gaps need %.0fpx, box is %.0fpx"
                % (entries, button[1], separation, needed, menu[3] - menu[1]))
    if needed > menu[3] - menu[1]:
        problems.append(
            "the menu shows up to %d buttons needing %.0fpx but its box is only "
            "%.0fpx tall — the last entry spills past the bottom"
            % (entries, needed, menu[3] - menu[1]))
    if button[0] > menu[2] - menu[0]:
        problems.append(
            "menu buttons are %.0fpx wide in a %.0fpx box"
            % (button[0], menu[2] - menu[0]))
    label_width = text_width("WIT HEADQUARTERS", int(scalar(screen_src, "MENU_FONT_SIZE")))
    if label_width > button[0] - 24.0:
        problems.append(
            "the longest menu label needs %.0fpx at %dpx font, inside a %.0fpx button"
            % (label_width, int(scalar(screen_src, "MENU_FONT_SIZE")), button[0]))

    # --- the wordmark fits its own box ---------------------------------------
    blocks = re.findall(r"\{[^{}]*\"text\":[^{}]*\}", logo_src, re.DOTALL)
    if len(blocks) < 3:
        problems.append("could not read the three wordmark rows out of title_logo.gd")
    total = 0.0
    for block in blocks:
        text = re.search(r'"text": "(.*?)"', block).group(1)
        size = int(re.search(r'"size": (\d+)', block).group(1))
        height = float(re.search(r'"height": ([-\d.]+)', block).group(1))
        width = text_width(text, size)
        total = max(total, float(re.search(r'"y": ([-\d.]+)', block).group(1)) + height)
        rows.append("  wordmark %-14s %dpx needs %.0fx%.0f in %.0fx%.0f"
                    % (text[:14], size, width, line_height(size),
                       scalar(logo_src, "WIDTH"), height))
        if width > scalar(logo_src, "WIDTH"):
            problems.append(
                "'%s' needs %.0fpx at %dpx font but the wordmark box is %.0fpx wide"
                % (text, width, size, scalar(logo_src, "WIDTH")))
        if line_height(size) > height:
            problems.append(
                "'%s' is %.0fpx tall at %dpx font in a %.0fpx row"
                % (text, line_height(size), size, height))
    if total > scalar(logo_src, "BOX_HEIGHT"):
        problems.append(
            "the wordmark rows run to %.0fpx but BOX_HEIGHT says %.0fpx, so the "
            "box the layout checks against is smaller than the type in it"
            % (total, scalar(logo_src, "BOX_HEIGHT")))

    # --- the record line's three lines fit -----------------------------------
    record_size = int(re.search(
        r'\[node name="RecordLabel".*?theme_override_font_sizes/font_size = (\d+)',
        read(scene), re.DOTALL).group(1))
    # "Claims filed", "Powers absorbed", and the active combo: three at most.
    record_needed = 3 * line_height(record_size)
    rows.append("  record line: 3 lines at %dpx need %.0fpx, box is %.0fpx"
                % (record_size, record_needed, record[3] - record[1]))
    if record_needed > record[3] - record[1]:
        problems.append(
            "the record line can show 3 lines needing %.0fpx at %dpx, in a %.0fpx box"
            % (record_needed, record_size, record[3] - record[1]))

    # --- the backdrop covers the widest phone --------------------------------
    overscan = scalar(splash_src, "OVERSCAN")
    revealed = (DESIGN[1] * WIDEST_ASPECT - DESIGN[0]) / 2.0
    rows.append("  backdrop overscan: %.0fpx each side, a 20:9 phone reveals %.0fpx"
                % (overscan, revealed))
    if overscan < revealed:
        problems.append(
            "OVERSCAN is %.0fpx but a 20:9 phone reveals %.0fpx past each side of "
            "the design box — the sky would end mid-screen" % (overscan, revealed))

    for row in rows:
        print(row)

    if problems:
        print("\nFAIL")
        for problem in problems:
            print(f" - {problem}")
        return 1

    print("\nThe title screen composes: every box is inside the frame and clear "
          "of the others.")
    return 0


if __name__ == "__main__":
    sys.exit(main())
