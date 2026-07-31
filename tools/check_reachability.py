#!/usr/bin/env python3
"""Reachability analysis: can the player actually get from spawn to exit?

Models the tuned jump arc from player.gd and BFS's the surface graph.
This is the check that would have caught the original 97px-jump bug.
"""
import re, sys, math
from pathlib import Path
from collections import deque

ROOT = Path(__file__).resolve().parent.parent

# --- movement constants, mirrored from scripts/player/player.gd -------------
MOVE_SPEED   = 360.0
JUMP_V       = 640.0
DJUMP_V      = 580.0
G_RISE       = 1500.0
G_FALL       = 2100.0
CAPSULE_HALF = 22.0     # collision capsule half height
MARGIN       = 0.85     # only trust 85% of theoretical reach (mobile imprecision)

SINGLE_RISE = JUMP_V ** 2 / (2 * G_RISE)              # 136.5
T_APEX_1    = JUMP_V / G_RISE                          # 0.427
DJUMP_RISE  = DJUMP_V ** 2 / (2 * G_RISE)              # 112.1
DOUBLE_RISE = SINGLE_RISE + DJUMP_RISE                 # 248.6
T_APEX_2    = DJUMP_V / G_RISE

def reach_run(rise, double):
    """Max horizontal distance while arriving at a surface `rise` px above."""
    apex = DOUBLE_RISE if double else SINGLE_RISE
    if rise > apex:
        return -1.0
    t_up = (T_APEX_1 + T_APEX_2) if double else T_APEX_1
    t_down = math.sqrt(2.0 * max(apex - rise, 0.0) / G_FALL)
    return MOVE_SPEED * (t_up + t_down) * MARGIN

# --- scene parsing ----------------------------------------------------------
# instanced platform scenes -> collision size
INSTANCED = {"moving_platform.tscn": (160.0, 28.0)}

def parse_room(path):
    text = path.read_text()
    shapes = {m.group(1): (float(m.group(2)), float(m.group(3))) for m in re.finditer(
        r'\[sub_resource type="RectangleShape2D" id="([^"]+)"\]\s*\nsize = Vector2\(([-\d.]+), ([-\d.]+)\)', text)}
    ext = {m.group(2): m.group(1).split("/")[-1] for m in re.finditer(
        r'\[ext_resource type="PackedScene" path="([^"]+)" id="([^"]+)"\]', text)}

    blocks = re.split(r'\n(?=\[node )', text)
    surfaces, spawn, exit_rect = [], None, None

    for b in blocks:
        m = re.match(r'\[node name="([^"]+)"(.*?)\]', b)
        if not m:
            continue
        name, attrs = m.group(1), m.group(2)
        pos = re.search(r'^position = Vector2\(([-\d.]+), ([-\d.]+)\)', b, re.M)
        px, py = (float(pos.group(1)), float(pos.group(2))) if pos else (0.0, 0.0)

        if name == "SpawnPoint":
            spawn = (px, py)
            continue

        # instanced moving platforms count as surfaces at both travel extremes
        inst = re.search(r'instance=ExtResource\("([^"]+)"\)', attrs)
        if inst and ext.get(inst.group(1)) in INSTANCED:
            w, h = INSTANCED[ext[inst.group(1)]]
            tv = re.search(r'^travel = Vector2\(([-\d.]+), ([-\d.]+)\)', b, re.M)
            tx, ty = (float(tv.group(1)), float(tv.group(2))) if tv else (0.0, 0.0)
            for ox, oy in ((0.0, 0.0), (tx, ty)):
                surfaces.append({"name": f"{name}@{int(ox)},{int(oy)}",
                                 "top": py + oy - h / 2,
                                 "x0": px + ox - w / 2, "x1": px + ox + w / 2})
            continue

        if 'type="StaticBody2D"' not in attrs and 'type="AnimatableBody2D"' not in attrs:
            if name == "Exit" and 'type="Area2D"' in attrs:
                # the shape lives in the Exit's child Shape node
                sm = re.search(r'\[node name="Shape" type="CollisionShape2D" parent="Exit"\]\s*\n'
                               r'shape = SubResource\("([^"]+)"\)', text)
                if sm and sm.group(1) in shapes:
                    w, h = shapes[sm.group(1)]
                    exit_rect = (px - w / 2, px + w / 2, py - h / 2, py + h / 2)
            continue

        # the body's own collision shape lives in the following child block
        idx = text.find(b)
        tail = text[idx:idx + 1200]
        sm = re.search(r'\[node name="Shape" type="CollisionShape2D" parent="[^"]*/'
                       + re.escape(name) + r'"\]\s*\nshape = SubResource\("([^"]+)"\)', tail)
        if not sm or sm.group(1) not in shapes:
            continue
        w, h = shapes[sm.group(1)]
        if h > w:      # tall+thin == wall, not a standing surface
            continue
        surfaces.append({"name": name, "top": py - h / 2,
                         "x0": px - w / 2, "x1": px + w / 2})
    return surfaces, spawn, exit_rect

def gap(a, b):
    if b["x1"] < a["x0"]:
        return a["x0"] - b["x1"]
    if b["x0"] > a["x1"]:
        return b["x0"] - a["x1"]
    return 0.0

def can_reach(a, b):
    """Returns (ok, needs_double, rise, run)."""
    rise = a["top"] - b["top"]          # >0 means b is higher
    run = gap(a, b)
    for double in (False, True):
        limit = reach_run(rise, double)
        if limit >= 0 and run <= limit:
            return True, double, rise, run
    return False, False, rise, run

def analyse(path):
    surfaces, spawn, exit_rect = parse_room(path)
    problems, notes = [], []
    if spawn is None:
        return [f"{path.name}: no SpawnPoint"], []

    start = None
    for s in surfaces:
        if s["x0"] <= spawn[0] <= s["x1"] and s["top"] >= spawn[1]:
            if start is None or s["top"] < start["top"]:
                start = s
    if start is None:
        return [f"{path.name}: spawn at {spawn} is not above any surface"], []

    # BFS over the surface graph
    reached = {start["name"]}
    q = deque([start])
    while q:
        cur = q.popleft()
        for s in surfaces:
            if s["name"] in reached:
                continue
            ok, _, _, _ = can_reach(cur, s)
            if ok:
                reached.add(s["name"])
                q.append(s)

    for s in surfaces:
        if s["name"] not in reached:
            best = None
            for o in surfaces:
                if o["name"] in reached:
                    _, _, rise, run = can_reach(o, s)
                    if best is None or (rise, run) < best[0]:
                        best = ((rise, run), o["name"])
            detail = f" closest from {best[1]}: rise {best[0][0]:.0f}px run {best[0][1]:.0f}px" if best else ""
            problems.append(f"{path.name}: UNREACHABLE platform '{s['name']}' (top y={s['top']:.0f}).{detail}")

    if exit_rect:
        ex0, ex1, ey0, ey1 = exit_rect
        supported = False
        for s in surfaces:
            if s["name"] not in reached:
                continue
            stand = s["top"] - CAPSULE_HALF
            if s["x1"] >= ex0 and s["x0"] <= ex1 and ey0 <= stand <= ey1:
                supported = True
                notes.append(f"{path.name}: exit reachable from '{s['name']}'")
                break
        if not supported:
            problems.append(f"{path.name}: EXIT NOT REACHABLE (rect x[{ex0:.0f},{ex1:.0f}] y[{ey0:.0f},{ey1:.0f}])")
    else:
        problems.append(f"{path.name}: no Exit found")
    return problems, notes

print(f"jump budget: single rise {SINGLE_RISE:.0f}px, double rise {DOUBLE_RISE:.0f}px, "
      f"flat run single {reach_run(0, False):.0f}px, double {reach_run(0, True):.0f}px "
      f"(at {int(MARGIN*100)}% margin)\n")

all_problems = []
for room in sorted((ROOT / "scenes/rooms").glob("test_room_*.tscn")):
    problems, notes = analyse(room)
    for n in notes:
        print("  ok:", n)
    all_problems += problems

if all_problems:
    print("\nFAIL")
    for p in all_problems:
        print(" -", p)
    sys.exit(1)
print("\nAll rooms fully traversable.")
