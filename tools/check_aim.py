#!/usr/bin/env python3
"""Model the aiming rules in player.gd and assert the properties that matter.

Shots used to travel on `position.x += direction * speed`, purely horizontal.
GAME_DESIGN.md section 6 asks for "mild vertical correction toward nearby
enemies", and without it the Ember Imp -- the only flying peril -- floats
above every shot the player fires, so the counterplay it is built around
(shoot it during the dive telegraph to cancel the dive) can never happen.

Aiming is now: hold up, or down in mid-air, to tilt the shot; otherwise a
capped assist leans it toward the nearest enemy inside a forward cone.

"Mild" is the whole design constraint, and it is exactly the sort of thing
that rots into homing missiles one tuning pass at a time. So this asserts:

  * the correction never exceeds the cap, for any target placement at all
  * a shot can therefore never travel backwards, or perpendicular
  * targets behind the player, or beyond range, are not tracked
  * the nearest target inside the cone is the one chosen
  * explicit tilt beats the assist and lands in the expected quadrant
  * and the case that motivated this: a shot at an Ember Imp overhead, which
    misses horizontally and connects with the assist

Run from the repository root:  python3 tools/check_aim.py
"""

from __future__ import annotations

import math
import re
import sys
from pathlib import Path

ROOT = Path(__file__).resolve().parent.parent
PLAYER = ROOT / "scripts" / "player" / "player.gd"


def exported(name: str, default: float) -> float:
    """Read an @export default straight out of player.gd so the model cannot
    drift away from the code it is modelling."""
    match = re.search(rf"@export var {name}: float = ([0-9.]+)", PLAYER.read_text(encoding="utf-8"))
    return float(match.group(1)) if match else default


TILT = exported("aim_tilt_degrees", 45.0)
RANGE = exported("aim_assist_range", 560.0)
CONE = exported("aim_assist_cone_degrees", 42.0)
MAX_CORRECTION = exported("aim_assist_max_correction_degrees", 20.0)

# Collision radii, from the scene files.
PROJECTILE_RADIUS = 6.0
IMP_HURTBOX_RADIUS = 19.0

# The design envelope, as absolute numbers.
#
# Every behavioural check below reads the tuning constants out of player.gd,
# which means widening a constant would otherwise widen the assertion with it
# and the check would keep passing while the feature turned into an aimbot.
# These bounds are the part that cannot move without someone editing this file
# and reading why.
BOUNDS = {
    # Above ~30 degrees the assist stops leaning the shot and starts placing
    # it: section 6 asks for "mild". Below 5 it does nothing at all.
    "aim_assist_max_correction_degrees": (5.0, 30.0),
    # The viewport is 1280x720. Past ~700px the assist covers most of what is
    # on screen, which is a different feature from helping with what is near.
    "aim_assist_range": (200.0, 700.0),
    # Narrower than the correction cap and the cone can select targets it
    # cannot lean toward; wider than 60 and it is selecting behind the player.
    "aim_assist_cone_degrees": (15.0, 60.0),
    "aim_tilt_degrees": (20.0, 70.0),
}


def angle_to(a: tuple[float, float], b: tuple[float, float]) -> float:
    """Godot's Vector2.angle_to: signed angle from a to b."""
    return math.atan2(a[0] * b[1] - a[1] * b[0], a[0] * b[0] + a[1] * b[1])


def rotated(v: tuple[float, float], angle: float) -> tuple[float, float]:
    cos_a, sin_a = math.cos(angle), math.sin(angle)
    return (v[0] * cos_a - v[1] * sin_a, v[0] * sin_a + v[1] * cos_a)


def assisted(forward: tuple[float, float], origin: tuple[float, float],
             enemies: list[tuple[float, float]]) -> tuple[float, float]:
    """player.gd::_assisted"""
    cone = math.radians(CONE)
    best = None
    best_distance = RANGE
    for enemy in enemies:
        offset = (enemy[0] - origin[0], enemy[1] - origin[1])
        distance = math.hypot(*offset)
        if distance >= best_distance or distance < 1.0:
            continue
        if abs(angle_to(forward, offset)) > cone:
            continue
        best = enemy
        best_distance = distance
    if best is None:
        return forward
    limit = math.radians(MAX_CORRECTION)
    to_target = (best[0] - origin[0], best[1] - origin[1])
    correction = max(-limit, min(limit, angle_to(forward, to_target)))
    return rotated(forward, correction)


def aim(facing: int, origin: tuple[float, float], enemies: list[tuple[float, float]],
        up: bool = False, down: bool = False, airborne: bool = False,
        horizontal: bool = True) -> tuple[float, float]:
    """player.gd::aim_direction"""
    forward = (float(facing), 0.0)
    tilt = 0.0
    if up:
        tilt = -1.0
    elif down and airborne:
        tilt = 1.0
    if tilt != 0.0:
        if not horizontal:
            return (0.0, tilt)
        return rotated(forward, math.radians(TILT) * tilt * facing)
    return assisted(forward, origin, enemies)


def hits(origin: tuple[float, float], direction: tuple[float, float],
         target: tuple[float, float], radius: float, travel: float) -> bool:
    """Does a shot from origin along direction pass within radius of target
    before running out of range? Closest approach on a segment."""
    to_target = (target[0] - origin[0], target[1] - origin[1])
    along = to_target[0] * direction[0] + to_target[1] * direction[1]
    if along < 0.0 or along > travel:
        return False
    closest = (origin[0] + direction[0] * along, origin[1] + direction[1] * along)
    return math.hypot(target[0] - closest[0], target[1] - closest[1]) <= radius


def main() -> int:
    problems: list[str] = []
    notes: list[str] = []
    origin = (0.0, 0.0)
    limit = math.radians(MAX_CORRECTION)

    notes.append(f"tilt {TILT:.0f} deg, assist cone {CONE:.0f} deg, "
                 f"cap {MAX_CORRECTION:.0f} deg, range {RANGE:.0f}px")

    # 0. The tuning constants themselves, against the absolute envelope.
    values = {
        "aim_assist_max_correction_degrees": MAX_CORRECTION,
        "aim_assist_range": RANGE,
        "aim_assist_cone_degrees": CONE,
        "aim_tilt_degrees": TILT,
    }
    for name, (low, high) in BOUNDS.items():
        value = values[name]
        if not low <= value <= high:
            problems.append(
                f"{name} = {value:g} is outside the design envelope "
                f"[{low:g}, {high:g}] -- see BOUNDS in this file for why")
    if CONE < MAX_CORRECTION:
        problems.append(
            f"aim_assist_cone_degrees ({CONE:g}) is narrower than "
            f"aim_assist_max_correction_degrees ({MAX_CORRECTION:g}): the cone "
            f"would select targets the cap cannot lean toward")
    notes.append("0. tuning constants inside the design envelope")

    # 1. The cap holds for every target placement inside the cone. This is the
    #    property that stops the assist becoming a homing missile.
    worst = 0.0
    for degrees in range(-90, 91, 1):
        for distance in (30.0, 120.0, 300.0, 559.0):
            angle = math.radians(degrees)
            enemy = (math.cos(angle) * distance, math.sin(angle) * distance)
            result = aim(1, origin, [enemy])
            worst = max(worst, abs(angle_to((1.0, 0.0), result)))
    notes.append(f"1. worst correction over 728 placements: {math.degrees(worst):.1f} deg")
    if worst > limit + 1e-6:
        problems.append(
            f"assist corrected {math.degrees(worst):.1f} deg, above the "
            f"{MAX_CORRECTION:.0f} deg cap")

    # 2. Which means a shot can never go backwards or sideways.
    if worst >= math.radians(90.0):
        problems.append("a shot can be corrected to perpendicular or worse")
    notes.append("2. forward component always positive (cap < 90 deg)")

    # 3. A target behind the player is not tracked at all.
    behind = aim(1, origin, [(-200.0, -40.0)])
    if abs(angle_to((1.0, 0.0), behind)) > 1e-9:
        problems.append("assist tracked a target behind the player")
    notes.append("3. target behind the player: no correction")

    # 4. Beyond range, no correction -- distance is what makes it a *local*
    #    assist rather than a screen-wide aimbot.
    far = aim(1, origin, [(RANGE + 10.0, -60.0)])
    if abs(angle_to((1.0, 0.0), far)) > 1e-9:
        problems.append("assist tracked a target beyond aim_assist_range")
    notes.append(f"4. target at {RANGE + 10:.0f}px: no correction")

    # 5. Nearest inside the cone wins, not first-found.
    near_target = (100.0, -30.0)
    result = aim(1, origin, [(400.0, 100.0), near_target, (500.0, -20.0)])
    # Expected is the same model run against the near target alone, so this
    # tests selection only and stays honest whatever the cone is tuned to.
    expected = assisted((1.0, 0.0), origin, [near_target])
    if abs(angle_to(result, expected)) > 1e-9:
        problems.append("assist did not choose the nearest target inside the cone")
    notes.append("5. nearest of three targets chosen")

    # 6. Explicit tilt, in every combination, lands in the right quadrant.
    cases = [
        ("up + right", dict(facing=1, up=True), (1, -1)),
        ("up + left", dict(facing=-1, up=True), (-1, -1)),
        ("down + right (airborne)", dict(facing=1, down=True, airborne=True), (1, 1)),
        ("down + left (airborne)", dict(facing=-1, down=True, airborne=True), (-1, 1)),
    ]
    for label, kwargs, (want_x, want_y) in cases:
        # A target sitting in the opposite quadrant must not pull the shot:
        # explicit aim wins.
        result = aim(origin=origin, enemies=[(200.0 * -want_x, 200.0 * -want_y)], **kwargs)
        got = (int(math.copysign(1, result[0])), int(math.copysign(1, result[1])))
        if got != (want_x, want_y):
            problems.append(f"tilt '{label}' aimed {got}, expected {(want_x, want_y)}")
    notes.append("6. all four tilt quadrants correct, and unmoved by the assist")

    straight_up = aim(1, origin, [], up=True, horizontal=False)
    if not (abs(straight_up[0]) < 1e-9 and straight_up[1] < 0.0):
        problems.append(f"up with no horizontal input aimed {straight_up}, expected straight up")
    notes.append("7. up with no horizontal input fires straight up")

    # 8. The case this exists for. An Ember Imp hovering overhead, at a
    #    distance a player would actually shoot from.
    imp = (240.0, -95.0)
    radius = PROJECTILE_RADIUS + IMP_HURTBOX_RADIUS
    horizontal_only = hits(origin, (1.0, 0.0), imp, radius, RANGE)
    with_assist = hits(origin, aim(1, origin, [imp]), imp, radius, RANGE)
    gap = abs(imp[1])
    notes.append(f"8. Ember Imp {gap:.0f}px overhead at {imp[0]:.0f}px: "
                 f"horizontal shot {'hits' if horizontal_only else 'MISSES'}, "
                 f"assisted shot {'hits' if with_assist else 'MISSES'}")
    if horizontal_only:
        problems.append("the Ember Imp case does not actually reproduce the old miss")
    if not with_assist:
        problems.append("the assist still misses an Ember Imp hovering overhead")

    # 9. But not from across the room: past the cap's reach the player still
    #    has to aim. Assist is help, not autoplay.
    steep = (120.0, -160.0)   # ~53 deg up, outside the 42 deg cone
    if hits(origin, aim(1, origin, [steep]), steep, radius, RANGE):
        problems.append("assist connected with a target outside the cone; it is too strong")
    notes.append("9. steeply-placed target outside the cone still needs manual aim")

    for note in notes:
        print(f"  {note}")

    if problems:
        print("\nFAIL")
        for problem in problems:
            print(f" - {problem}")
        return 1

    print("\nAim assist stays mild, and the flying peril is hittable.")
    return 0


if __name__ == "__main__":
    sys.exit(main())
