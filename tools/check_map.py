#!/usr/bin/env python3
"""Generate thousands of Claim Maps and assert every structural invariant.

The Claim Map is the run. If a generated map has a dead end, an unreachable
node, or a row the player cannot get past, the run is unfinishable -- and it
would only happen on the seeds that produce it, which is the worst possible
bug to find by playing, and impossible to find at all without a Godot binary.

So the generator's rules live in scripts/map/claim_map.gd as constants, this
reads those constants out of the source so the two cannot drift apart on
tuning, and then it re-implements the algorithm and hammers it.

Asserted over every seed:

  structure   every node is reachable from a row-0 node
              every node has a route onward to the boss (no dead ends)
              every act has exactly one boss, and every route passes through it
              rows are contiguous: no row is empty between two populated rows
  readability no two edges cross between adjacent rows
  design      row 0 is always combat; the row before a boss is always a rest
              no shop leads into a shop, no rest into a rest
              at most one mini-boss per act
  pacing      the expected run length lands inside §5's 20-35 minute window

Run from the repository root:  python3 tools/check_map.py
"""

from __future__ import annotations

import random
import re
import sys
from pathlib import Path

ROOT = Path(__file__).resolve().parent.parent
SOURCE = (ROOT / "scripts" / "map" / "claim_map.gd").read_text(encoding="utf-8")

SEEDS = 4000

PERIL, HIGH_RISK, OFFICE, CLAIM_EVENT, MINI_BOSS, SALVAGE, BOSS = range(7)
KIND_NAMES = ["PERIL", "HIGH_RISK", "OFFICE", "CLAIM_EVENT", "MINI_BOSS", "SALVAGE", "BOSS"]


def constant(name: str) -> int:
    match = re.search(rf"^const {name} := (\d+)", SOURCE, re.MULTILINE)
    if match is None:
        raise SystemExit(f"claim_map.gd has no `const {name}`")
    return int(match.group(1))


def weights() -> dict[int, int]:
    block = re.search(r"const WEIGHTS := \{(.*?)\}", SOURCE, re.DOTALL)
    if block is None:
        raise SystemExit("claim_map.gd has no WEIGHTS block")
    found = {}
    for name, value in re.findall(r"Kind\.(\w+):\s*(\d+)", block.group(1)):
        found[KIND_NAMES.index(name)] = int(value)
    return found


ACTS = constant("ACTS")
CHOICE_ROWS = constant("CHOICE_ROWS")
WIDTH = constant("WIDTH")
PATHS = constant("PATHS")
WEIGHTS = weights()
NO_REPEAT = {OFFICE, SALVAGE, MINI_BOSS}
ONCE_PER_ACT = {MINI_BOSS}

# Seconds a node of each kind takes, for the pacing estimate. Combat rooms are
# timed against the existing rooms; the rest are read-and-decide screens.
DURATION = {
    PERIL: 75, HIGH_RISK: 90, OFFICE: 25, CLAIM_EVENT: 20,
    MINI_BOSS: 65, SALVAGE: 20, BOSS: 100,
}
CARD_PICK_SECONDS = 12
# §5's window applies to a typical run, so it is checked against the average.
TARGET_MINUTES = (20, 35)
# The extremes get a wider band. A player who routes around every fight really
# should finish faster -- and arrive at the boss with no Premiums, no cards and
# no chance, which is the route punishing itself. What must not happen is a
# route so short or so long that it is a different game.
SANITY_MINUTES = (14, 40)
# Nodes along a route that actually offered a branch. The whole point of the
# structure is choosing your exposure; a route with almost no forks is a
# corridor wearing a map. Carved paths converge, so an individual route can
# legitimately be narrow -- it is the average that has to carry the design,
# with a floor to catch a generator that has stopped branching at all.
MIN_AVERAGE_FORKS = 6.0
MIN_ROUTE_FORKS = 2


class Map:
    def __init__(self, seed: int):
        self.rng = random.Random(seed)
        self.nodes: list[dict] = []
        self.by_cell: dict[tuple[int, int, int], int] = {}
        for act in range(ACTS):
            self.carve_act(act)
        self.assign_kinds()
        self.link_acts()

    # -- generation, mirroring claim_map.gd --------------------------------

    def ensure(self, act: int, row: int, col: int) -> int:
        key = (act, row, col)
        if key in self.by_cell:
            return self.by_cell[key]
        node_id = len(self.nodes)
        self.nodes.append({"id": node_id, "act": act, "row": row, "col": col,
                           "kind": PERIL, "next": []})
        self.by_cell[key] = node_id
        return node_id

    def link(self, from_id: int, to_id: int) -> None:
        if to_id not in self.nodes[from_id]["next"]:
            self.nodes[from_id]["next"].append(to_id)

    def crosses(self, act: int, row: int, from_col: int, to_col: int) -> bool:
        for node in self.nodes:
            if node["act"] != act or node["row"] != row or node["col"] == from_col:
                continue
            for next_id in node["next"]:
                other_to = self.nodes[next_id]["col"]
                if from_col < node["col"] and to_col > other_to:
                    return True
                if from_col > node["col"] and to_col < other_to:
                    return True
        return False

    def pick_next_column(self, act: int, row: int, col: int) -> int:
        options: list[int] = []
        for step in (-1, 0, 1):
            candidate = max(0, min(WIDTH - 1, col + step))
            if candidate not in options and not self.crosses(act, row, col, candidate):
                options.append(candidate)
        if not options:
            return col
        return options[self.rng.randint(0, len(options) - 1)]

    def carve_act(self, act: int) -> None:
        boss_id = self.ensure(act, CHOICE_ROWS, 0)
        self.nodes[boss_id]["kind"] = BOSS
        for _ in range(PATHS):
            col = self.rng.randint(0, WIDTH - 1)
            for row in range(CHOICE_ROWS):
                from_id = self.ensure(act, row, col)
                if row == CHOICE_ROWS - 1:
                    self.link(from_id, boss_id)
                    break
                next_col = self.pick_next_column(act, row, col)
                self.link(from_id, self.ensure(act, row + 1, next_col))
                col = next_col

    def row_ids(self, act: int, row: int) -> list[int]:
        ids = [n["id"] for n in self.nodes if n["act"] == act and n["row"] == row]
        return sorted(ids, key=lambda i: self.nodes[i]["col"])

    def assign_kinds(self) -> None:
        for act in range(ACTS):
            used: set[int] = set()
            for row in range(CHOICE_ROWS):
                for node_id in self.row_ids(act, row):
                    kind = self.pick_kind(row, node_id, used)
                    self.nodes[node_id]["kind"] = kind
                    if kind in ONCE_PER_ACT:
                        used.add(kind)

    def pick_kind(self, row: int, node_id: int, used: set[int]) -> int:
        if row == 0:
            return PERIL
        if row == CHOICE_ROWS - 1:
            return SALVAGE
        banned = set(used)
        for other in self.nodes:
            if node_id in other["next"] and other["kind"] in NO_REPEAT:
                banned.add(other["kind"])
        pool = [k for k in WEIGHTS if k not in banned]
        if not pool:
            return PERIL
        total = sum(WEIGHTS[k] for k in pool)
        roll = self.rng.randint(0, total - 1)
        for kind in pool:
            roll -= WEIGHTS[kind]
            if roll < 0:
                return kind
        return PERIL

    def link_acts(self) -> None:
        for act in range(ACTS - 1):
            boss_id = self.by_cell[(act, CHOICE_ROWS, 0)]
            for node_id in self.row_ids(act + 1, 0):
                self.link(boss_id, node_id)

    # -- queries -----------------------------------------------------------

    def starts(self) -> list[int]:
        return self.row_ids(0, 0)

    def final_boss(self) -> int:
        return self.by_cell[(ACTS - 1, CHOICE_ROWS, 0)]

    def reachable(self) -> set[int]:
        seen, stack = set(), list(self.starts())
        while stack:
            node_id = stack.pop()
            if node_id in seen:
                continue
            seen.add(node_id)
            stack.extend(self.nodes[node_id]["next"])
        return seen

    def reaches_boss(self) -> set[int]:
        """Nodes with any route to the final boss (reverse reachability)."""
        incoming: dict[int, list[int]] = {n["id"]: [] for n in self.nodes}
        for node in self.nodes:
            for next_id in node["next"]:
                incoming[next_id].append(node["id"])
        seen, stack = set(), [self.final_boss()]
        while stack:
            node_id = stack.pop()
            if node_id in seen:
                continue
            seen.add(node_id)
            stack.extend(incoming[node_id])
        return seen

    def routes(self, limit: int = 400) -> list[list[int]]:
        """Enumerate routes start -> final boss, capped."""
        found: list[list[int]] = []

        def walk(node_id: int, path: list[int]) -> None:
            if len(found) >= limit:
                return
            path = path + [node_id]
            nxt = self.nodes[node_id]["next"]
            if not nxt:
                found.append(path)
                return
            for child in nxt:
                walk(child, path)

        for start in self.starts():
            walk(start, [])
        return found


def main() -> int:
    problems: list[str] = []
    route_lengths: list[int] = []
    durations: list[float] = []
    forks: list[int] = []
    kind_totals = {k: 0 for k in range(7)}
    node_totals: list[int] = []

    print(f"  {ACTS} acts x ({CHOICE_ROWS} choice rows + boss), width {WIDTH}, "
          f"{PATHS} carved paths, {SEEDS} seeds")

    for seed in range(SEEDS):
        game_map = Map(seed)
        node_totals.append(len(game_map.nodes))

        reachable = game_map.reachable()
        if len(reachable) != len(game_map.nodes):
            orphans = sorted(set(range(len(game_map.nodes))) - reachable)[:4]
            problems.append(f"seed {seed}: {len(game_map.nodes) - len(reachable)} "
                            f"unreachable node(s), e.g. {orphans}")

        onward = game_map.reaches_boss()
        dead = sorted(set(range(len(game_map.nodes))) - onward)[:4]
        if dead:
            problems.append(f"seed {seed}: dead-end node(s) with no route to the "
                            f"final boss, e.g. {dead}")

        for act in range(ACTS):
            bosses = [n for n in game_map.nodes
                      if n["act"] == act and n["kind"] == BOSS]
            if len(bosses) != 1:
                problems.append(f"seed {seed}: act {act} has {len(bosses)} bosses")
            minis = [n for n in game_map.nodes
                     if n["act"] == act and n["kind"] == MINI_BOSS]
            if len(minis) > 1:
                problems.append(f"seed {seed}: act {act} has {len(minis)} mini-bosses")
            for row in range(CHOICE_ROWS + 1):
                if not game_map.row_ids(act, row):
                    problems.append(f"seed {seed}: act {act} row {row} is empty")

        for node in game_map.nodes:
            kind_totals[node["kind"]] += 1
            if node["row"] == 0 and node["kind"] != PERIL:
                problems.append(f"seed {seed}: act {node['act']} opens on "
                                f"{KIND_NAMES[node['kind']]}, not combat")
            if node["row"] == CHOICE_ROWS - 1 and node["kind"] != SALVAGE:
                problems.append(f"seed {seed}: no rest before act {node['act']}'s boss")
            if node["kind"] in NO_REPEAT:
                for next_id in node["next"]:
                    if game_map.nodes[next_id]["kind"] == node["kind"]:
                        problems.append(
                            f"seed {seed}: {KIND_NAMES[node['kind']]} leads straight "
                            f"into another one (node {node['id']} -> {next_id})")

        # Crossed edges, checked on the finished graph rather than during carve.
        for act in range(ACTS):
            for row in range(CHOICE_ROWS):
                edges = [(n["col"], game_map.nodes[t]["col"])
                         for n in game_map.nodes
                         if n["act"] == act and n["row"] == row
                         for t in n["next"]]
                for i, (a_from, a_to) in enumerate(edges):
                    for b_from, b_to in edges[i + 1:]:
                        if (a_from < b_from and a_to > b_to) or \
                           (a_from > b_from and a_to < b_to):
                            problems.append(
                                f"seed {seed}: crossed edges in act {act} row {row}")

        if seed < 200:      # route enumeration is the expensive part
            for route in game_map.routes():
                route_lengths.append(len(route))
                seconds = sum(DURATION[game_map.nodes[i]["kind"]] for i in route)
                seconds += CARD_PICK_SECONDS * (len(route) - 1)
                durations.append(seconds / 60.0)
                # A map is only a map if it asks questions. Count the nodes
                # along this route that actually offered somewhere to go.
                forks.append(sum(1 for i in route
                                 if len(game_map.nodes[i]["next"]) > 1))

    expected_length = ACTS * (CHOICE_ROWS + 1)
    if route_lengths and (min(route_lengths) != expected_length
                          or max(route_lengths) != expected_length):
        problems.append(
            f"routes vary in length ({min(route_lengths)}-{max(route_lengths)}); "
            f"every route should visit exactly {expected_length} nodes")

    shortest, longest = min(durations), max(durations)
    average = sum(durations) / len(durations)
    print(f"  nodes per map: {min(node_totals)}-{max(node_totals)}, "
          f"{expected_length} visited per run")
    print(f"  run length: {shortest:.0f}-{longest:.0f} min, average {average:.0f} min "
          f"(§5 target {TARGET_MINUTES[0]}-{TARGET_MINUTES[1]})")
    if not TARGET_MINUTES[0] <= average <= TARGET_MINUTES[1]:
        problems.append(f"the average route is {average:.0f} min, outside §5's "
                        f"{TARGET_MINUTES[0]}-{TARGET_MINUTES[1]} minute window")
    if shortest < SANITY_MINUTES[0]:
        problems.append(f"the fastest route is {shortest:.0f} min, under the "
                        f"{SANITY_MINUTES[0]} minute sanity floor")
    if longest > SANITY_MINUTES[1]:
        problems.append(f"the slowest route is {longest:.0f} min, over the "
                        f"{SANITY_MINUTES[1]} minute sanity ceiling")

    mean_forks = sum(forks) / len(forks)
    print(f"  choices offered: {min(forks)}-{max(forks)} per route, "
          f"average {mean_forks:.1f} (of {expected_length} nodes)")
    if mean_forks < MIN_AVERAGE_FORKS:
        problems.append(
            f"routes average {mean_forks:.1f} real choices, below {MIN_AVERAGE_FORKS}; "
            f"this is a corridor with a map screen in front of it")
    if min(forks) < MIN_ROUTE_FORKS:
        problems.append(
            f"some route offers only {min(forks)} real choice(s), below the "
            f"floor of {MIN_ROUTE_FORKS}")

    total_kinds = sum(kind_totals.values())
    spread = "  ".join(f"{KIND_NAMES[k].lower()} {kind_totals[k] * 100.0 / total_kinds:.0f}%"
                       for k in range(7) if kind_totals[k])
    print(f"  node mix: {spread}")

    if problems:
        unique = sorted(set(problems))
        print(f"\nFAIL ({len(problems)} across {SEEDS} seeds, {len(unique)} distinct)")
        for problem in unique[:12]:
            print(f" - {problem}")
        return 1

    print(f"\nEvery map over {SEEDS} seeds is connected, dead-end free and paced to spec.")
    return 0


if __name__ == "__main__":
    sys.exit(main())
