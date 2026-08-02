#!/usr/bin/env python3
"""Simulate the air-jump budget and assert it cannot be exceeded.

tools/check_reachability.py proves every room is traversable *given* a jump
budget. That proof is worthless if the player can exceed the budget, and two
ways to do exactly that shipped:

  1. `_try_jump` allowed an air jump whenever the player held a card granting
     bonus air jumps, without checking the remaining count -- so one card
     meant unlimited mid-air jumps, i.e. flight.
  2. `_process_wall` refilled the air jump on *every* cling frame, so
     wall-jump away -> double-jump back -> cling -> refill climbed a single
     flat wall forever.

Either one lets a player skip all of the platforming the rooms are built
around. This models the rules in scripts/player/player.gd and checks the
budget holds, then re-checks that the moves the rules are meant to allow
(chimney climbing between two facing walls) still work.

Run from the repository root:  python3 tools/check_movement.py
"""

from __future__ import annotations

import re
import sys
from pathlib import Path

ROOT = Path(__file__).resolve().parent.parent
PLAYER = ROOT / "scripts" / "player" / "player.gd"


class Monster:
    """The subset of player.gd state that governs the air-jump budget."""

    def __init__(self, bonus_air_jumps: int = 0, base_air_jumps: int = 1):
        self.base = base_air_jumps
        self.bonus = bonus_air_jumps
        self.on_floor = True
        self.air_jumps_left = self.max_air_jumps()
        self.refilled_wall_normal = 0.0
        self.jumps_used = 0

    def max_air_jumps(self) -> int:
        return self.base + self.bonus

    def leave_ground(self) -> None:
        self.on_floor = False

    def land(self) -> None:
        self.on_floor = True
        self.air_jumps_left = self.max_air_jumps()
        self.refilled_wall_normal = 0.0

    def cling(self, wall_normal: float) -> bool:
        """Grab a wall. Returns True if this cling refilled the air jump."""
        if _sign(wall_normal) == _sign(self.refilled_wall_normal):
            return False
        self.refilled_wall_normal = wall_normal
        self.air_jumps_left = self.max_air_jumps()
        return True

    def air_jump(self) -> bool:
        """Try a mid-air jump. Returns True if it was allowed."""
        if self.on_floor or self.air_jumps_left <= 0:
            return False
        self.air_jumps_left -= 1
        self.jumps_used += 1
        return True


def _sign(value: float) -> float:
    return 0.0 if value == 0.0 else (1.0 if value > 0.0 else -1.0)


def check_source() -> list[str]:
    """Guard against the exact source shapes that caused each exploit."""
    text = PLAYER.read_text(encoding="utf-8")
    problems = []
    if re.search(r"air_jumps_left > 0 or _bonus_air_jumps\(\) > 0", text):
        problems.append(
            "player.gd: air jump is gated on `air_jumps_left > 0 or "
            "_bonus_air_jumps() > 0`; the second clause is always true while a "
            "bonus-air-jump card is held, so the counter never runs out")
    wall = re.search(r"func _process_wall.*?(?=\nfunc )", text, re.DOTALL)
    if wall is None:
        problems.append("player.gd: _process_wall not found")
    elif "air_jumps_left = _max_air_jumps()" in wall.group(0) \
            and "_refilled_wall_normal" not in wall.group(0):
        problems.append(
            "player.gd: _process_wall refills the air jump on every cling "
            "frame, which permits an unbounded single-wall climb")
    return problems


def main() -> int:
    results = []
    problems = check_source()

    # 1. No card: one airtime gives exactly one double jump.
    monster = Monster(bonus_air_jumps=0)
    monster.leave_ground()
    allowed = sum(1 for _ in range(50) if monster.air_jump())
    results.append(f"1. no card: {allowed} mid-air jump(s) per airtime")
    if allowed != 1:
        problems.append(f"expected exactly 1 air jump with no card, got {allowed}")

    # 2. Two stacks of the +1 air jump card: three, and then no more. This is
    #    the case that used to be unlimited.
    monster = Monster(bonus_air_jumps=2)
    monster.leave_ground()
    allowed = sum(1 for _ in range(50) if monster.air_jump())
    results.append(f"2. +2 air jumps from cards: {allowed} mid-air jump(s), not unlimited")
    if allowed != 3:
        problems.append(f"expected exactly 3 air jumps with +2 from cards, got {allowed}")

    # 3. Single flat wall: cling refills once, and never again until you touch
    #    the floor or a wall facing the other way.
    monster = Monster()
    monster.leave_ground()
    monster.air_jump()
    refills = sum(1 for _ in range(20) if monster.cling(1.0))
    results.append(f"3. one flat wall: {refills} refill(s) over 20 clings")
    if refills != 1:
        problems.append(f"expected 1 refill on a single wall, got {refills}")

    # 4. And the climb it used to enable is now bounded: alternating
    #    wall-jump / double-jump / re-cling on the SAME wall gains nothing
    #    after the first cycle.
    monster = Monster()
    monster.leave_ground()
    cycles_with_a_jump = 0
    for _ in range(10):
        monster.cling(-1.0)          # same wall every time
        if monster.air_jump():
            cycles_with_a_jump += 1
    results.append(f"4. same-wall climb: {cycles_with_a_jump} of 10 cycles produced a jump")
    if cycles_with_a_jump != 1:
        problems.append(
            f"same-wall climbing produced {cycles_with_a_jump} jumps; expected 1")

    # 5. Chimney climbing between two facing walls must still work -- the fix
    #    must not cost the move it was protecting.
    monster = Monster()
    monster.leave_ground()
    cycles_with_a_jump = 0
    for i in range(10):
        monster.cling(1.0 if i % 2 == 0 else -1.0)
        if monster.air_jump():
            cycles_with_a_jump += 1
    results.append(f"5. alternating walls: {cycles_with_a_jump} of 10 cycles produced a jump")
    if cycles_with_a_jump != 10:
        problems.append(
            f"chimney climbing broke: {cycles_with_a_jump} of 10 cycles worked")

    for line in results:
        print(f"  {line}")

    if problems:
        print("\nFAIL")
        for problem in problems:
            print(f" - {problem}")
        return 1

    print("\nAir-jump budget holds; wall chains intact.")
    return 0


if __name__ == "__main__":
    sys.exit(main())
