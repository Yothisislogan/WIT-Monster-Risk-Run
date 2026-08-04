#!/usr/bin/env python3
"""Hold every boss to the contract its own header comment claims to obey.

All three boss scripts open with the same list of design rules — telegraph for
at least half a second, end every attack in a punish window, make the window
genuinely safe to stand in, three phases. Those rules are the fight. They are
also, right now, a comment: nothing checks them, there is no Godot here to
play a boss and find out, and a boss whose punish window still deals contact
damage is a fight that is simply unfair with no error anywhere.

This is the only checker that found a bug in shipped content before it was
written to catch one. Both existing bosses granted IMPACT_DASH on death, so
beating the Actuary handed you a power you already had, and the combination
system had one reachable pair out of a possible six.

What it checks, per boss:

  * every `*_tell` timing is at least TELL_FLOOR, including after the phase
    speed-up multiplies it down
  * contact damage is suppressed during the punish window, the intro and death
  * damage taken is doubled during the punish window
  * every attack state routes into the punish window, so no attack can end
    with the boss immediately attacking again
  * three phases keyed to health
  * boss_spawned and boss_health_changed are emitted, and die() records the
    defeat and grants an ability
  * the granted ability exists, and no two bosses grant the same one
  * the boss scene exists, is instanced by a room, and the room is registered
    in LevelData.ROOMS and BOSS_ROOMS

And across the set: every pair of abilities has a combo defined, because a
missing pair is invisible in play.

Run from the repository root:  python3 tools/check_bosses.py
"""

from __future__ import annotations

import re
import sys
from pathlib import Path

ROOT = Path(__file__).resolve().parent.parent

## The punish-window state each boss uses. Different names, same contract.
PUNISH_STATE = {
    "boss_inferno_adjuster": "STUNNED",
    "boss_actuary": "EXPOSED",
    "boss_high_water_mark": "BEACHED",
    "boss_fine_print": "SAGGING",
    "boss_total_loss": "WRECKED",
    "boss_claims_swarm": "SCATTERED",
    "boss_underwriter": "OVERDRAWN",
}
## The half-second reaction floor from §16, restated once here as the rule the
## bosses are held to rather than read from any one of them.
TELL_FLOOR = 0.5


def read(path: Path) -> str:
    return path.read_text(encoding="utf-8")


def strip_comments(source: str) -> str:
    return "\n".join(line.split("#")[0] for line in source.splitlines())


def exports(source: str) -> dict[str, float]:
    """Every `@export var name: float = value` in the file."""
    return {name: float(value) for name, value in re.findall(
        r"^@export var (\w+): (?:float|int) = ([-\d.]+)", source, re.MULTILINE)}


def main() -> int:
    problems: list[str] = []
    rows: list[str] = []

    level_data = read(ROOT / "scripts" / "level_data.gd")
    abilities_src = read(ROOT / "scripts" / "abilities.gd")
    # ABILITIES is keyed by the CONSTANT (FLAME_DRAFT: {...}), while COMBOS and
    # the saved profile are keyed by the string it holds ("flame_draft"), so
    # the constants have to be resolved before the two can be compared.
    ability_consts = dict(re.findall(r'^const (\w+) := "(\w+)"',
                                     abilities_src, re.MULTILINE))
    ability_ids = {ability_consts[name] for name
                   in re.findall(r'^\t(\w+): \{', abilities_src, re.MULTILINE)
                   if name in ability_consts}
    boss_rooms = re.findall(r'"(res://scenes/rooms/boss_\w+\.tscn)"', level_data)

    scripts = sorted((ROOT / "scripts" / "enemies").glob("boss_*.gd"))
    if not scripts:
        problems.append("no boss scripts found at all")
    granted: dict[str, str] = {}

    for path in scripts:
        key = path.stem
        source = read(path)
        code = strip_comments(source)
        punish = PUNISH_STATE.get(key)
        if punish is None:
            problems.append(
                f"{key} is a boss this checker does not know. Add it to "
                f"PUNISH_STATE — an unlisted boss is an unchecked boss")
            continue

        # --- telegraphs -----------------------------------------------------
        tells = {n: v for n, v in exports(source).items() if n.endswith("_tell")}
        if not tells:
            problems.append(f"{key} declares no `*_tell` timing; every attack "
                            f"must telegraph (§16)")
        worst = 1.0
        speed = re.search(r"speed_scale := 1\.0 - ([\d.]+) \* float\(_phase - 1\)", code)
        if speed:
            worst = 1.0 - float(speed.group(1)) * 2.0   # three phases
        for name, value in sorted(tells.items()):
            floored = "TELL_FLOOR" in code and "maxf(" in code
            effective = value * worst
            rows.append(f"  {key}: {name} {value:.2f}s, x{worst:.2f} at phase 3 "
                        f"= {effective:.2f}s{' (floored)' if floored else ''}")
            if value < TELL_FLOOR:
                problems.append(
                    f"{key}: {name} is {value:.2f}s, under the {TELL_FLOOR}s "
                    f"telegraph floor (§16)")
            elif effective < TELL_FLOOR and not floored:
                problems.append(
                    f"{key}: {name} is {value:.2f}s but the phase speed-up cuts "
                    f"it to {effective:.2f}s, under the {TELL_FLOOR}s floor, and "
                    f"nothing clamps it")

        # --- the punish window is real --------------------------------------
        guard = re.search(r"func _on_hitbox_body_entered.*?\n\n", code, re.DOTALL)
        if guard is None or f"State.{punish}" not in guard.group(0):
            problems.append(
                f"{key}: contact damage is not suppressed during State.{punish}. "
                f"A punish window you cannot stand in is a bluff")
        for required in ("INTRO", "DYING"):
            if guard is not None and f"State.{required}" not in guard.group(0):
                problems.append(
                    f"{key}: contact damage is not suppressed during "
                    f"State.{required}")
        if not re.search(rf"2 if _state == State\.{punish} else 1", code):
            problems.append(
                f"{key}: take_damage does not double during State.{punish}, so "
                f"there is no reward for waiting for the window")

        # --- every attack ends somewhere safe --------------------------------
        states = re.search(r"enum State \{(.*?)\}", code, re.DOTALL)
        names = [s.strip() for s in states.group(1).replace("\n", " ").split(",")] \
            if states else []
        names = [n for n in names if n]
        attack_states = [n for n in names
                         if n not in ("INTRO", "IDLE", "HOVER", "DYING", punish)
                         and not n.endswith("_TELL")]
        # Resolve each attack state's match block, then follow the helpers it
        # calls. The previous version of this loop could not fail: its fallback
        # was `all(f"State.{punish}" in code for _ in exits)`, whose condition
        # does not mention the loop variable, so it only ever asked "does the
        # punish state appear anywhere in this file" -- true for every boss.
        # Twelve attack states across four bosses were waved through by it, and
        # a deliberately chained attack was not caught. CLAUDE.md is explicit
        # that a checker which has never failed is not known to work.
        helpers = {name: body for name, body in re.findall(
            r"^func (_\w+)\(.*?\).*?:\n(.*?)(?=\n\nfunc |\n\n#|\Z)",
            code, re.MULTILINE | re.DOTALL)}

        match_body = re.search(r"\tmatch _state:\n(.*?)(?=\n\n)", code, re.DOTALL)
        blocks: dict[str, str] = {}
        if match_body:
            parts = re.split(r"\n\t\tState\.(\w+):\n", "\n" + match_body.group(1))
            for i in range(1, len(parts) - 1, 2):
                blocks[parts[i]] = parts[i + 1]

        def routes_to_punish(body: str, seen: set[str] | None = None) -> bool:
            """True if this block reaches the punish state: directly, through a
            helper it calls, or by handing off to another state that does.

            The hand-off case is why this follows transitions and not just
            calls. The Inferno Adjuster's SLAM_RISE enters SLAM_DROP, which
            calls _land_slam(), which enters STUNNED -- a legitimate two-part
            attack. What the rule is actually against is a CYCLE among attack
            states with no exit, which is what "chain attacks forever" means;
            `seen` makes such a cycle terminate as False instead of recursing.
            """
            seen = seen if seen is not None else set()
            if re.search(rf"_enter\(State\.{punish}\b", body):
                return True
            for call in re.findall(r"\b(_\w+)\(", body):
                if call in seen or call not in helpers:
                    continue
                seen.add(call)
                if routes_to_punish(helpers[call], seen):
                    return True
            for nxt in re.findall(r"_enter\(State\.(\w+)", body):
                # A hand-off THROUGH a telegraph is a new attack starting, not
                # the same one finishing, so it does not count as a route to
                # the window. That is the whole distinction: SLAM_RISE ->
                # SLAM_DROP is one attack in two parts and is fine, while
                # BREAKER -> DELUGE_TELL is two attacks back to back with no
                # window in between, which is exactly what rule 4 forbids.
                if nxt.endswith("_TELL"):
                    continue
                token = "state:" + nxt
                if token in seen or nxt not in blocks:
                    continue
                seen.add(token)
                if routes_to_punish(blocks[nxt], seen):
                    return True
            return False

        for state in attack_states:
            body = blocks.get(state)
            if body is None:
                problems.append(
                    f"{key}: State.{state} has no arm in the _physics_process "
                    f"match, so nothing drives it and it can never end")
                continue
            if not routes_to_punish(body):
                problems.append(
                    f"{key}: State.{state} has no route into State.{punish}; "
                    f"an attack that does not end in the punish window means "
                    f"the boss can chain attacks forever")

        # --- phases, events, death ------------------------------------------
        if code.count("phase = 3") < 1 or code.count("phase = 2") < 1:
            problems.append(f"{key}: does not key three phases to health (§16)")
        for signal_call in ("Events.boss_spawned.emit", "Events.boss_health_changed.emit"):
            if signal_call not in code:
                problems.append(f"{key}: never calls {signal_call}")
        die = re.search(r"func die\(\).*", code, re.DOTALL)
        die_body = die.group(0) if die else ""
        for required in ("GameManager.record_boss_defeated()",
                         "GameManager.record_enemy_defeated()",
                         "defeated.emit()"):
            if required not in die_body:
                problems.append(f"{key}: die() does not call {required}")
        grant = re.search(r"GameManager\.grant_ability\(Abilities\.(\w+)\)", die_body)
        if grant is None:
            problems.append(
                f"{key}: die() grants no ability. Absorbing the boss's power is "
                f"the reward for the fight (§12)")
        else:
            const_name = grant.group(1)
            ability = ability_consts.get(const_name)
            if ability is None or ability not in ability_ids:
                problems.append(
                    f"{key}: grants Abilities.{const_name}, which is not an "
                    f"entry in Abilities.ABILITIES")
            elif ability in granted:
                problems.append(
                    f"{key} and {granted[ability]} both grant '{ability}'. Two "
                    f"bosses handing out the same power means one of the fights "
                    f"rewards you with something you already have, and it "
                    f"shrinks how many combinations (§14) are reachable")
            else:
                granted[ability] = key
                rows.append(f"  {key}: grants {ability}")

        # --- it is actually reachable in a run -------------------------------
        scene = ROOT / "scenes" / "enemies" / f"{key}.tscn"
        if not scene.exists():
            problems.append(f"{key}: no scene at scenes/enemies/{key}.tscn")
        room = ROOT / "scenes" / "rooms" / f"{key}.tscn"
        if not room.exists():
            problems.append(f"{key}: no boss room at scenes/rooms/{key}.tscn")
        else:
            if f"scenes/enemies/{key}.tscn" not in read(room):
                problems.append(f"{key}: its room does not instance its scene")
            if f'"{key}"' not in level_data:
                problems.append(
                    f"{key}: no LevelData.ROOMS entry, so the banner and the "
                    f"music fall back to UNSURVEYED RISK")
            if f"res://scenes/rooms/{key}.tscn" not in boss_rooms:
                problems.append(
                    f"{key}: not in LevelData.BOSS_ROOMS, so no act ever "
                    f"routes to it and the fight is unreachable")

    # --- every boss can actually be drawn -------------------------------------
    # A run has ClaimMap.ACTS boss slots. If those slots are filled by indexing
    # BOSS_ROOMS with the act number, only the first ACTS entries are ever
    # reachable and every boss past that is content nobody can see -- which is
    # exactly what happened at seven bosses and three acts. The fix is to deal
    # from a pool shuffled by the map's own seeded generator, so this asserts
    # the shuffle is still there.
    # Comments stripped first: the explanatory comment in _assign_rooms names
    # boss_room_for(act) as the thing it replaced, and a raw search would match
    # the explanation and report the bug it is explaining.
    claim_map = strip_comments(read(ROOT / "scripts" / "map" / "claim_map.gd"))
    acts = int(re.search(r"^const ACTS := (\d+)", claim_map, re.MULTILINE).group(1))
    rows.append(f"  {acts} boss slots per run, drawn from {len(boss_rooms)} bosses")
    if len(boss_rooms) < acts:
        problems.append(
            f"a run has {acts} boss slots but BOSS_ROOMS lists only "
            f"{len(boss_rooms)}, so a run must repeat a fight")
    if "_shuffle(bosses)" not in claim_map:
        problems.append(
            "claim_map.gd no longer shuffles the boss pool before dealing. "
            "Indexing BOSS_ROOMS by act number makes every boss past the first "
            f"{acts} unreachable in every run -- content nobody will ever see, "
            "with nothing anywhere reporting an error")
    if re.search(r"boss_room_for\(", claim_map):
        problems.append(
            "claim_map.gd is back to calling boss_room_for(act), which cycles "
            "the list by act index and hides every boss past the first " + str(acts))

    # --- across the set -------------------------------------------------------
    rows.append(f"  {len(scripts)} bosses, {len(ability_ids)} abilities, "
                f"{len(boss_rooms)} rooms in the act rotation")
    if scripts and len(boss_rooms) < len(scripts):
        problems.append(
            f"{len(scripts)} bosses exist but BOSS_ROOMS lists {len(boss_rooms)}; "
            f"a boss that is never routed to is content nobody will see")

    combos = set(re.findall(r'^\t"([\w|]+)": \{', abilities_src, re.MULTILINE))
    ids = sorted(ability_ids)
    missing = []
    for i in range(len(ids)):
        for j in range(i + 1, len(ids)):
            if f"{ids[i]}|{ids[j]}" not in combos:
                missing.append(f"{ids[i]}|{ids[j]}")
    rows.append(f"  {len(combos)} combos for {len(ids) * (len(ids) - 1) // 2} pairs")
    if missing:
        problems.append(
            "no combo defined for " + ", ".join(missing) + ". A missing pair is "
            "invisible in play: the player just never sees a combo and cannot "
            "tell whether that is the design or a gap (§14)")

    for row in rows:
        print(row)

    if problems:
        print("\nFAIL")
        for problem in problems:
            print(f" - {problem}")
        return 1

    print("\nEvery boss telegraphs, ends in a real punish window, and grants a "
          "power no other boss grants.")
    return 0


if __name__ == "__main__":
    sys.exit(main())
