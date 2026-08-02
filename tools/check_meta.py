#!/usr/bin/env python3
"""Check the WIT Headquarters economy and the Case File table.

§24 asks for permanent progression and, in the same breath, warns against the
thing permanent progression always becomes: stat boosts that make the game
easier until it is boring, gated behind a grind long enough that you feel the
gate. Both failure modes are arithmetic, so both are checkable here rather
than discovered ten runs in by a player who then stops playing.

Asserted:

  power     the total permanent stat gain, fully bought, stays under a share
            of a starting run. Unlocks do not count toward it -- opening a
            card into the pool is not power, it is choice.
  grind     buying the whole catalogue takes a number of runs inside a band.
            Too many and the gate is the game; too few and there is nothing
            to come back for.
  payout    a losing run still pays enough to be worth finishing
  ordering  no upgrade rank costs less than the rank below it
  unlocks   every card id an upgrade claims to unlock is a real card, every
            locked card is unlocked by something, and nothing common is
            locked -- run one should be a smaller catalogue, not a worse one
  files     every Case File condition names a field the claim report carries

Run from the repository root:  python3 tools/check_meta.py
"""

from __future__ import annotations

import ast
import re
import sys
from pathlib import Path

ROOT = Path(__file__).resolve().parent.parent
HQ = (ROOT / "scripts" / "meta" / "headquarters.gd").read_text(encoding="utf-8")
FILES_SRC = (ROOT / "scripts" / "meta" / "case_files.gd").read_text(encoding="utf-8")
CARD_DB = (ROOT / "scripts" / "cards" / "card_db.gd").read_text(encoding="utf-8")
GAME_MANAGER = (ROOT / "scripts" / "autoload" / "game_manager.gd").read_text(encoding="utf-8")

# A fully-bought profile may not add more than this share of a standard
# starting policy in raw Coverage. Past it, the meta is playing the game.
MAX_COVERAGE_SHARE = 0.35
# Runs to buy everything, assuming a middling run.
GRIND_BAND = (12, 40)
# A run that ends badly must still be worth finishing.
MIN_LOSING_RUN_FILES = 10


def constant(source: str, name: str) -> float:
    match = re.search(rf"^const {name} := (-?[\d.]+)", source, re.MULTILINE)
    if match is None:
        raise SystemExit(f"missing `const {name}`")
    return float(match.group(1))


def gd_dicts(source: str, table: str) -> list[dict]:
    """Parse a GDScript table of flat dictionaries into Python.

    GDScript dictionary literals are close enough to Python's that this only
    has to strip comments, drop trailing commas and translate `true`/`false`.
    Anything more exotic than a literal in these tables is a design smell in
    its own right.
    """
    block = re.search(rf"const {table} := \[(.*?)\n\]", source, re.DOTALL)
    if block is None:
        raise SystemExit(f"missing `const {table}`")
    text = block.group(1)
    text = re.sub(r"#[^\n]*", "", text)
    text = text.replace("true", "True").replace("false", "False")
    text = re.sub(r"(\d)_(\d)", r"\1\2", text)
    text = re.sub(r",(\s*[\}\]])", r"\1", text)
    try:
        return ast.literal_eval("[" + text + "]")
    except (ValueError, SyntaxError) as error:
        raise SystemExit(f"could not parse {table}: {error}")


def card_ids() -> set[str]:
    return set(re.findall(r'\{"id": "(\w+)"', CARD_DB))


def common_card_ids() -> set[str]:
    """Cards with no explicit rarity are common."""
    common = set()
    for chunk in re.finditer(r'\{"id": "(\w+)"(.*?)(?=\n\t\{"id"|\n\s*\n|\n\])',
                             CARD_DB, re.DOTALL):
        if "Rarity." not in chunk.group(2):
            common.add(chunk.group(1))
    return common


def report_fields() -> set[str]:
    block = re.search(r"func build_claim_report.*?\n\t\}", GAME_MANAGER, re.DOTALL)
    if block is None:
        raise SystemExit("game_manager.gd has no build_claim_report()")
    return set(re.findall(r'^\t\t"(\w+)":', block.group(0), re.MULTILINE))


def main() -> int:
    problems: list[str] = []
    upgrades = gd_dicts(HQ, "UPGRADES")
    files = gd_dicts(FILES_SRC, "FILES")
    locked = ast.literal_eval("[" + re.sub(
        r",(\s*\])", r"\1",
        re.search(r"const LOCKED_BY_DEFAULT := \[(.*?)\]", HQ, re.DOTALL).group(1)) + "]")
    known_cards = card_ids()

    # -- ordering and total cost -------------------------------------------
    total_cost = 0
    for upgrade in upgrades:
        costs = upgrade["costs"]
        total_cost += sum(costs)
        if len(costs) != upgrade["ranks"]:
            problems.append(f"{upgrade['id']}: {len(costs)} costs for "
                            f"{upgrade['ranks']} ranks")
        if any(b <= a for a, b in zip(costs, costs[1:])):
            problems.append(f"{upgrade['id']}: rank costs do not increase ({costs})")

    # -- power ceiling ------------------------------------------------------
    coverage_gain = sum(u.get("per_rank", 0) * u["ranks"] for u in upgrades)
    standard = float(re.search(r'"standard":.*?"coverage": (\d+)',
                               GAME_MANAGER, re.DOTALL).group(1))
    share = coverage_gain / standard
    if share > MAX_COVERAGE_SHARE:
        problems.append(
            f"a fully-bought profile adds {coverage_gain:.0f} Coverage to a "
            f"{standard:.0f} baseline ({share:.0%}), over the {MAX_COVERAGE_SHARE:.0%} "
            f"ceiling — at that point the meta is playing the game")

    stat_upgrades = [u for u in upgrades if any(
        k in u for k in ("per_rank", "currency", "energy", "risk", "umbrella"))]
    unlock_upgrades = [u for u in upgrades if any(
        k in u for k in ("unlocks_cards", "unlocks_exclusions"))]
    if len(unlock_upgrades) < len(stat_upgrades) / 2:
        problems.append(
            f"{len(stat_upgrades)} stat upgrades to {len(unlock_upgrades)} unlocks; "
            f"§24's warning is that this becomes a stat shop")

    # -- grind --------------------------------------------------------------
    per_site = constant(HQ, "FILES_PER_SITE")
    per_boss = constant(HQ, "FILES_PER_BOSS")
    for_win = constant(HQ, "FILES_FOR_WIN")
    per_file = constant(HQ, "FILES_PER_NEW_CASE_FILE")

    # A middling run: reaches act two, kills one boss, files nothing new.
    middling = per_site * 8 + per_boss
    # A bad run: four sites, no boss.
    losing = per_site * 4
    # A good run: all 18 sites, three bosses, a win, one new Case File.
    winning = per_site * 18 + per_boss * 3 + for_win + per_file

    runs_middling = total_cost / middling
    runs_winning = total_cost / winning
    print(f"  catalogue: {len(upgrades)} upgrades ({len(stat_upgrades)} stat, "
          f"{len(unlock_upgrades)} unlock), {total_cost} Case Files total")
    print(f"  a losing run files {losing:.0f}, a middling run {middling:.0f}, "
          f"a winning run {winning:.0f}")
    print(f"  full catalogue: {runs_middling:.0f} middling runs, "
          f"{runs_winning:.0f} winning runs")
    print(f"  permanent Coverage gain: +{coverage_gain:.0f} on {standard:.0f} "
          f"({share:.0%} of baseline)")

    if losing < MIN_LOSING_RUN_FILES:
        problems.append(f"a losing run files only {losing:.0f} Case Files; below "
                        f"{MIN_LOSING_RUN_FILES} there is no reason to finish one")
    if not GRIND_BAND[0] <= runs_middling <= GRIND_BAND[1]:
        problems.append(
            f"the catalogue takes {runs_middling:.0f} middling runs, outside the "
            f"{GRIND_BAND[0]}-{GRIND_BAND[1]} band")

    # -- unlocks ------------------------------------------------------------
    unlocked_by_upgrades: set[str] = set()
    for upgrade in upgrades:
        for card in upgrade.get("unlocks_cards", []):
            unlocked_by_upgrades.add(card)
            if card not in known_cards:
                problems.append(f"{upgrade['id']} unlocks '{card}', which is not a card")
    for card in locked:
        if card not in known_cards:
            problems.append(f"LOCKED_BY_DEFAULT lists '{card}', which is not a card")
        if card not in unlocked_by_upgrades:
            problems.append(f"'{card}' is locked by default and nothing unlocks it")
    for card in unlocked_by_upgrades - set(locked):
        problems.append(f"an upgrade unlocks '{card}', which was never locked")

    commons = common_card_ids()
    locked_commons = sorted(set(locked) & commons)
    if locked_commons:
        problems.append(
            f"common cards are locked ({', '.join(locked_commons)}); run one should "
            f"be a smaller catalogue, not a worse one")
    print(f"  cards: {len(known_cards)} total, {len(locked)} locked at first run "
          f"({len(known_cards) - len(locked)} available immediately)")

    # -- case files ---------------------------------------------------------
    fields = report_fields()
    for entry in files:
        for key in ("stat", "and_stat"):
            if key in entry and entry[key] not in fields:
                problems.append(
                    f"Case File '{entry['id']}' reads report field '{entry[key]}', "
                    f"which build_claim_report() does not produce")
        if "min" not in entry and "max" not in entry:
            problems.append(f"Case File '{entry['id']}' has no condition")
    ids = [entry["id"] for entry in files]
    if len(ids) != len(set(ids)):
        problems.append("duplicate Case File ids")
    print(f"  case files: {len(files)}")

    if problems:
        print("\nFAIL")
        for problem in sorted(set(problems)):
            print(f" - {problem}")
        return 1

    print("\nHeadquarters pays out, unlocks more than it inflates, and is buyable.")
    return 0


if __name__ == "__main__":
    sys.exit(main())
