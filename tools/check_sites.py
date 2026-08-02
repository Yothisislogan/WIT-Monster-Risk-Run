#!/usr/bin/env python3
"""Validate the Claim Map's site content in scripts/sites/site_db.gd.

Sites are data, which is the point -- adding a Claim Event is a dictionary
entry. It also means a typo in an effect name is not a syntax error anywhere;
it falls through apply()'s match to the default branch and the option silently
does nothing but print "Noted for the file." A player would read that as the
joke rather than the bug it is.

Asserted:

  * every option has a label, a detail, a cost and an effect
  * every effect kind is one apply() actually handles
  * every event offers at least two options, and at least one that costs
    nothing -- otherwise a player with no Premiums is staring at a wall
  * risk swings stay inside a sane band, and every event that can raise Risk
    also offers a way not to
  * the shop's price table covers every card rarity
  * labels and detail text fit the space the panel gives them

Run from the repository root:  python3 tools/check_sites.py
"""

from __future__ import annotations

import re
import sys
from pathlib import Path

ROOT = Path(__file__).resolve().parent.parent
SITE_DB = ROOT / "scripts" / "sites" / "site_db.gd"
POLICY_CARD = ROOT / "scripts" / "cards" / "policy_card.gd"

SOURCE = SITE_DB.read_text(encoding="utf-8")

MAX_RISK_SWING = 0.25
MAX_LABEL = 34
MAX_DETAIL = 120


def handled_effects() -> set[str]:
    """Effect kinds apply() has a match arm for."""
    body = re.search(r"static func apply\(.*?\n(?=\n\nstatic func|\Z)", SOURCE, re.DOTALL)
    if body is None:
        raise SystemExit("site_db.gd has no apply()")
    match_block = re.search(r'match String\(effect\.get\("kind".*?\n(\t\t.*?)\n\t# ',
                            body.group(0), re.DOTALL)
    text = match_block.group(1) if match_block else body.group(0)
    return set(re.findall(r'^\t\t"(\w+)":', text, re.MULTILINE))


def constants() -> dict[str, float]:
    """Named constants in site_db.gd, so a cost written as PATCH_COST rather
    than a literal still resolves."""
    found = {}
    for name, value in re.findall(r"^const (\w+) := (-?[\d.]+)$", SOURCE, re.MULTILINE):
        found[name] = float(value)
    return found


CONSTANTS = constants()


def number(text: str | None) -> float | None:
    """A literal, a named constant, or a base price wrapped in price(...).

    Shop costs are written as price(PATCH_COST) so they scale with the
    deductible at runtime. The scale is not knowable here; the base is, and
    the base is what the sanity checks below are about.
    """
    if text is None:
        return None
    text = text.strip()
    wrapped = re.fullmatch(r"price\((\w+)\)", text)
    if wrapped:
        text = wrapped.group(1)
    if re.fullmatch(r"-?[\d.]+", text):
        return float(text)
    return CONSTANTS.get(text)


def parse_options(block: str) -> list[dict]:
    """Pull every option dictionary out of GDScript source.

    Options are written three ways in this file -- inline in an array, spread
    across lines, and inside options.append(...) -- so rather than matching a
    layout, this finds each "label" key and brace-matches outward from it.
    """
    options = []
    for key in re.finditer(r'"label"\s*:', block):
        start = block.rfind("{", 0, key.start())
        if start < 0:
            continue
        depth, end = 0, -1
        for index in range(start, len(block)):
            if block[index] == "{":
                depth += 1
            elif block[index] == "}":
                depth -= 1
                if depth == 0:
                    end = index + 1
                    break
        if end < 0:
            continue
        text = block[start:end]
        label = re.search(r'"label":\s*"([^"]*)"', text)
        detail = re.search(r'"detail":\s*"((?:[^"\\]|\\.)*)"', text)
        cost = re.search(r'"cost":\s*(price\(\w+\)|[\w.-]+)', text)
        kind = re.search(r'"kind":\s*"(\w+)"', text)
        risk = re.search(r'"risk":\s*([\w.-]+)', text)
        value = re.search(r'"value":\s*([\w.-]+)', text)
        # The shop builds its card rows from CardDb, so their label, detail and
        # price are all expressions. Those are checked by check_economy.py
        # against the card table; here only the effect kind is knowable.
        dynamic = label is None
        options.append({
            "label": label.group(1) if label else None,
            "detail": detail.group(1) if detail else None,
            "cost": number(cost.group(1)) if cost else None,
            "kind": kind.group(1) if kind else None,
            "risk": number(risk.group(1)) or 0.0 if risk else 0.0,
            "value": number(value.group(1)) or 0.0 if value else 0.0,
            "dynamic": dynamic,
            "raw": text,
        })
    return options


def parse_events() -> list[dict]:
    block = re.search(r"const EVENTS := \[(.*?)\n\]", SOURCE, re.DOTALL)
    if block is None:
        raise SystemExit("site_db.gd has no EVENTS table")
    events = []
    for chunk in re.finditer(r'\{\s*\n\s*"title":\s*"([^"]+)",(.*?)\n\t\},',
                             block.group(1) + "\n\t},", re.DOTALL):
        events.append({"title": chunk.group(1), "options": parse_options(chunk.group(2))})
    return events


def main() -> int:
    problems: list[str] = []
    handled = handled_effects()
    events = parse_events()
    if not events:
        print("FAIL\n - parsed zero Claim Events; the EVENTS table or this parser is wrong")
        return 1

    # Options outside the EVENTS table too: the shop and the rest build theirs
    # in code, so scan the whole file for option literals.
    all_options = parse_options(SOURCE)

    total_options = 0
    for event in events:
        options = event["options"]
        total_options += len(options)
        title = event["title"]
        if len(options) < 2:
            problems.append(f"'{title}' offers {len(options)} option(s); an event with "
                            f"one answer is a cutscene")
        if not any(option["cost"] == 0 for option in options):
            problems.append(f"'{title}' has no free option; a player with no Premiums "
                            f"is stuck looking at it")
        raises_risk = [o for o in options if o["risk"] > 0
                       or (o["kind"] == "risk" and o["value"] > 0)]
        if raises_risk and len(raises_risk) == len(options):
            problems.append(f"'{title}' raises Risk whatever you pick; that is not a choice")

    dynamic_count = sum(1 for option in all_options if option["dynamic"])
    for option in all_options:
        if option["dynamic"]:
            # Only the effect kind is a literal on these.
            if option["kind"] is None:
                problems.append(f"a generated option has no effect kind: {option['raw'][:60]}")
            elif option["kind"] not in handled:
                problems.append(f"a generated option has effect kind '{option['kind']}', "
                                f"which apply() does not handle")
            continue
        label = option["label"] or "?"
        if option["detail"] is None:
            problems.append(f"option '{label}' has no detail text")
        if option["cost"] is None:
            problems.append(f"option '{label}' has no cost")
        elif option["cost"] < 0:
            problems.append(f"option '{label}' has a negative cost")
        if option["kind"] is None:
            problems.append(f"option '{label}' has no effect kind")
        elif option["kind"] not in handled:
            problems.append(f"option '{label}' has effect kind '{option['kind']}', which "
                            f"apply() does not handle — it would silently do nothing")
        if abs(option["risk"]) > MAX_RISK_SWING:
            problems.append(f"option '{label}' swings Risk by {option['risk']:+.2f}, "
                            f"beyond the {MAX_RISK_SWING} band")
        if option["kind"] == "risk" and abs(option["value"]) > MAX_RISK_SWING:
            problems.append(f"option '{label}' swings Risk by {option['value']:+.2f}, "
                            f"beyond the {MAX_RISK_SWING} band")
        if option["label"] and len(option["label"]) > MAX_LABEL:
            problems.append(f"option label '{label}' is {len(option['label'])} chars, "
                            f"over {MAX_LABEL} for the button")
        if option["detail"] and len(option["detail"]) > MAX_DETAIL:
            problems.append(f"option '{label}' detail is {len(option['detail'])} chars, "
                            f"over {MAX_DETAIL}")

    prices = re.search(r"const CARD_PRICES := \[([^\]]+)\]", SOURCE)
    rarities = len(re.findall(r"^\s*(COMMON|UNCOMMON|RARE)",
                              POLICY_CARD.read_text(encoding="utf-8"), re.MULTILINE))
    if prices:
        listed = len(prices.group(1).split(","))
        enum_size = len(re.search(r"enum Rarity \{([^}]*)\}",
                                  POLICY_CARD.read_text(encoding="utf-8")).group(1).split(","))
        if listed != enum_size:
            problems.append(f"CARD_PRICES lists {listed} prices for {enum_size} rarities")

    print(f"  {len(events)} claim events, {total_options} event options, "
          f"{len(all_options)} options total ({dynamic_count} generated from CardDb)")
    print(f"  effect kinds handled by apply(): {', '.join(sorted(handled))}")

    if problems:
        print("\nFAIL")
        for problem in sorted(set(problems)):
            print(f" - {problem}")
        return 1

    print("\nEvery site option is complete, affordable-by-someone and actually does something.")
    return 0


if __name__ == "__main__":
    sys.exit(main())
