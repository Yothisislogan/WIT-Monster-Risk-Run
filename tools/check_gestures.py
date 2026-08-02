#!/usr/bin/env python3
"""Model the touch gesture recogniser and prove its thresholds cannot overlap.

The seven on-screen buttons are gone; the right of the screen is now a gesture
surface. Buttons were unambiguous by construction — you either hit one or you
did not. Gestures are only unambiguous if their thresholds are ordered
correctly, and when they are not the failure is not a crash. It is a game that
jumps when you meant to dash, or fires a shot every time you jump, which reads
as "the controls are broken" and is almost impossible to diagnose by feel.

The orderings that have to hold:

    tap_slop  <  swipe_min_distance     or a tap is also a swipe
    tap_max_time  <  hold_start_time    or a tap starts a charge on the way past
    swipe must be reachable inside swipe_max_time by a human thumb

Those are checked as absolute design bounds, not just relative to each other,
so widening one constant cannot widen the assertion with it — the mistake
tools/check_aim.py shipped with the first time.

Then the classifier itself, mirrored from GestureControls.classify(), is run
over a grid of synthetic gestures and every one is required to resolve to
exactly one action.

Run from the repository root:  python3 tools/check_gestures.py
"""

from __future__ import annotations

import math
import re
import sys
from pathlib import Path

ROOT = Path(__file__).resolve().parent.parent
SOURCE = (ROOT / "scripts" / "ui" / "gesture_controls.gd").read_text(encoding="utf-8")
PLAYER = (ROOT / "scripts" / "player" / "player.gd").read_text(encoding="utf-8")


def exported(name: str, source: str = SOURCE) -> float:
    match = re.search(rf"@export var {name}: float = ([0-9.]+)", source)
    if match is None:
        raise SystemExit(f"no @export var {name}")
    return float(match.group(1))


TAP_TIME = exported("tap_max_time")
TAP_SLOP = exported("tap_slop")
SWIPE_DISTANCE = exported("swipe_min_distance")
SWIPE_TIME = exported("swipe_max_time")
HOLD_TIME = exported("hold_start_time")
MULTI_WINDOW = exported("multi_touch_window")
ACTION_HOLD = exported("action_hold_time")
JUMP_CUT_MIN_HOLD = exported("jump_cut_min_hold", PLAYER)

# Absolute envelope. These are human-thumb numbers on a ~1280x720 landscape
# viewport, not relative to each other, so no single constant can drift the
# assertion along with itself.
BOUNDS = {
    # Under 0.15s a deliberate tap gets missed; over 0.4s a hold reads as one.
    "tap_max_time": (0.15, 0.40),
    # Under 12px every hand tremor splits a tap; over 40px a short flick is a tap.
    "tap_slop": (12.0, 40.0),
    # Under 50px a sloppy tap swipes; over 140px a swipe crosses half the pad.
    "swipe_min_distance": (50.0, 140.0),
    # A thumb flick is 0.1-0.3s; allow slack, but not so much that a slow drag
    # to reposition the thumb registers as a dash.
    "swipe_max_time": (0.25, 0.60),
    # Long enough to clear a tap, short enough that charging feels immediate.
    "hold_start_time": (0.25, 0.55),
    "multi_touch_window": (0.10, 0.40),
    # Zero is invisible to is_action_just_pressed; long enough and a gesture
    # keeps the action down past the moment the player acts on it.
    "action_hold_time": (0.03, 0.10),
}


def classify(travel: tuple[float, float], duration: float) -> str:
    """GestureControls.classify(), mirrored."""
    length = math.hypot(*travel)
    if length >= SWIPE_DISTANCE and duration <= SWIPE_TIME:
        if abs(travel[0]) >= abs(travel[1]):
            return "dash_right" if travel[0] > 0.0 else "dash_left"
        return "down" if travel[1] > 0.0 else "special"
    if duration <= TAP_TIME and length <= TAP_SLOP:
        return "tap"
    return "none"


def main() -> int:
    problems: list[str] = []
    values = {
        "tap_max_time": TAP_TIME, "tap_slop": TAP_SLOP,
        "swipe_min_distance": SWIPE_DISTANCE, "swipe_max_time": SWIPE_TIME,
        "hold_start_time": HOLD_TIME, "multi_touch_window": MULTI_WINDOW,
        "action_hold_time": ACTION_HOLD,
    }
    print(f"  tap <= {TAP_TIME}s / {TAP_SLOP:.0f}px   swipe >= {SWIPE_DISTANCE:.0f}px "
          f"in <= {SWIPE_TIME}s   hold at {HOLD_TIME}s")

    # 0. The envelope.
    for name, (low, high) in BOUNDS.items():
        if not low <= values[name] <= high:
            problems.append(f"{name} = {values[name]:g} is outside the design "
                            f"envelope [{low:g}, {high:g}] — see BOUNDS in this file")

    # 1. Orderings. Each of these being wrong produces a specific, nasty bug.
    if TAP_SLOP >= SWIPE_DISTANCE:
        problems.append(
            f"tap_slop ({TAP_SLOP:g}) is not below swipe_min_distance "
            f"({SWIPE_DISTANCE:g}): a gesture could satisfy both, and a tap "
            f"would sometimes dash")
    if TAP_TIME >= HOLD_TIME:
        problems.append(
            f"tap_max_time ({TAP_TIME:g}) is not below hold_start_time "
            f"({HOLD_TIME:g}): every tap would start a charge on its way past, "
            f"so jumping would fire a shot")
    # A swipe must have left the tap window behind before the hold fires, or a
    # slow swipe charges the weapon mid-flight.
    thumb_speed = SWIPE_DISTANCE / HOLD_TIME
    if thumb_speed > 600.0:
        problems.append(
            f"a swipe must average {thumb_speed:.0f}px/s to clear the slop "
            f"before hold_start_time; above ~600 that is a flick, not a swipe")
    print(f"  a swipe clears the hold threshold at {thumb_speed:.0f}px/s")

    # 1b. Cross-file: a fired action must stay down long enough for a
    #     _physics_process to see is_action_just_pressed, and must come back up
    #     before player.gd would read the release as a deliberate jump cut.
    if ACTION_HOLD <= 1.0 / 60.0:
        problems.append(
            f"action_hold_time ({ACTION_HOLD:g}s) is not longer than one physics "
            f"frame; a press and release inside a frame is invisible to "
            f"is_action_just_pressed and the gesture would do nothing")
    if ACTION_HOLD >= JUMP_CUT_MIN_HOLD:
        problems.append(
            f"action_hold_time ({ACTION_HOLD:g}s) is not below player.gd's "
            f"jump_cut_min_hold ({JUMP_CUT_MIN_HOLD:g}s): releasing would cut "
            f"every tapped jump to a hop")
    print(f"  fired actions held {ACTION_HOLD}s "
          f"({ACTION_HOLD * 60:.1f} physics frames, cut threshold {JUMP_CUT_MIN_HOLD}s)")

    # 2. No gesture may be classifiable two ways. Exhaustive over a grid.
    ambiguous = 0
    checked = 0
    for degrees in range(0, 360, 5):
        angle = math.radians(degrees)
        for length in (0.0, 5.0, TAP_SLOP, TAP_SLOP + 1, SWIPE_DISTANCE - 1,
                       SWIPE_DISTANCE, SWIPE_DISTANCE + 40, 400.0):
            for duration in (0.01, TAP_TIME, TAP_TIME + 0.01, SWIPE_TIME,
                             SWIPE_TIME + 0.01, 2.0):
                travel = (math.cos(angle) * length, math.sin(angle) * length)
                checked += 1
                is_swipe = length >= SWIPE_DISTANCE and duration <= SWIPE_TIME
                is_tap = duration <= TAP_TIME and length <= TAP_SLOP
                if is_swipe and is_tap:
                    ambiguous += 1
    if ambiguous:
        problems.append(f"{ambiguous} of {checked} synthetic gestures satisfy both "
                        f"the tap and the swipe test")
    print(f"  {checked} synthetic gestures, {ambiguous} ambiguous")

    # 3. Directions resolve to the intended verb, including diagonals, which
    #    resolve on the dominant axis rather than being rejected.
    cases = [
        ("flick right", (200.0, 0.0), 0.15, "dash_right"),
        ("flick left", (-200.0, 0.0), 0.15, "dash_left"),
        ("flick up", (0.0, -200.0), 0.15, "special"),
        ("flick down", (0.0, 200.0), 0.15, "down"),
        ("diagonal up-right, mostly right", (180.0, -90.0), 0.15, "dash_right"),
        ("diagonal up-right, mostly up", (90.0, -180.0), 0.15, "special"),
        ("clean tap", (0.0, 0.0), 0.08, "tap"),
        ("tap with a wobble", (TAP_SLOP - 2, 0.0), 0.10, "tap"),
        ("slow drag, thumb repositioning", (300.0, 0.0), 1.2, "none"),
        ("long press, no movement", (2.0, 0.0), 1.5, "none"),
        ("short drag past the slop", (TAP_SLOP + 10, 0.0), 0.12, "none"),
    ]
    for label, travel, duration, expected in cases:
        got = classify(travel, duration)
        if got != expected:
            problems.append(f"'{label}' classified as {got}, expected {expected}")
    print(f"  {len(cases)} named gestures, all as intended" if not problems
          else f"  {len(cases)} named gestures checked")

    # 4. A slow drag must never dash. This is the one that would ruin the game:
    #    the movement thumb repositioning, or a hesitant swipe, firing a dash.
    for duration in (SWIPE_TIME + 0.05, 0.8, 1.5, 3.0):
        for length in (SWIPE_DISTANCE, 200.0, 600.0):
            if classify((length, 0.0), duration) != "none":
                problems.append(
                    f"a {length:.0f}px drag over {duration:.2f}s registered as a "
                    f"gesture; slow drags must be inert")

    # 5. Every verb the scheme claims to cover is actually reachable.
    reachable = {classify(t, d) for _, t, d, _ in cases}
    for verb in ("tap", "dash_left", "dash_right", "special", "down"):
        if verb not in reachable:
            problems.append(f"no gesture in the test set produces '{verb}'")

    if problems:
        print("\nFAIL")
        for problem in problems:
            print(f" - {problem}")
        return 1

    print("\nGesture thresholds are unambiguous and every verb is reachable.")
    return 0


if __name__ == "__main__":
    sys.exit(main())
