#!/usr/bin/env python3
"""Estimate whether UI text still fits the boxes it is drawn into.

The fonts were just raised by about 45% because they were unreadable on a
phone — the Risk readout was 13px and the ability readout was 14px at 40%
opacity. Raising type is the easy half. The half that breaks silently is
layout: a card whose description used to wrap to four lines now wraps to six,
overflows a fixed-height button, and gets clipped. There is no Godot here to
look at, and a screenshot is not available either, so the fit has to be
arithmetic.

This measures the real strings — card text from CardDb, site options from
SiteDb, upgrades from Headquarters, deductibles from GameManager — against the
real widths, taken from the panel geometry in the .tscn files, at the real
font sizes, taken from the code that builds each button.

The glyph metrics are an approximation of Godot's default font and are stated
as such. They are deliberately pessimistic: the check is meant to fail while
there is still headroom, not at the exact pixel where clipping begins.

Run from the repository root:  python3 tools/check_text_fit.py
"""

from __future__ import annotations

import math
import re
import sys
from pathlib import Path

ROOT = Path(__file__).resolve().parent.parent

# Godot's default font (Open Sans SemiBold), averaged over mixed-case English.
# Uppercase runs wider, so headings get the wider figure.
AVG_GLYPH = 0.52
UPPER_GLYPH = 0.60
# Line advance, including the theme's line_spacing of 4.
def line_height(size: int) -> float:
    return size * 1.32 + 4.0

# Fail while there is still room, not at the pixel where clipping starts.
HEADROOM = 1.08


def read(path: str) -> str:
    return (ROOT / path).read_text(encoding="utf-8")


def panel_box(scene: str, node: str) -> tuple[float, float]:
    """(width, height) of a centre-anchored panel, from its offsets. Read from
    the scene rather than restated here, so resizing the panel moves the
    assertion with it."""
    block = re.search(rf'\[node name="{node}".*?(?=\n\[node )', read(scene), re.DOTALL)
    if block is None:
        raise SystemExit(f"{scene} has no node named {node}")
    body = block.group(0)
    def offset(name: str) -> float:
        found = re.search(rf"^offset_{name} = ([-\d.]+)", body, re.MULTILINE)
        return float(found.group(1)) if found else 0.0
    return (offset("right") - offset("left"), offset("bottom") - offset("top"))


def code_size(source: str, anchor: str) -> int:
    """The font size the builder function applies, read from the code."""
    body = source[source.find(anchor):]
    found = re.search(r'add_theme_font_size_override\("font_size", (\d+)\)', body)
    if found is None:
        raise SystemExit(f"no font size found after {anchor!r}")
    return int(found.group(1))


def code_min_height(source: str, anchor: str) -> float:
    body = source[source.find(anchor):]
    found = re.search(r"custom_minimum_size = Vector2\(([-\d.]+), ([-\d.]+)\)", body)
    if found is None:
        raise SystemExit(f"no custom_minimum_size found after {anchor!r}")
    return float(found.group(2))


def wrapped_height(text: str, width: float, size: int, upper: bool = False) -> float:
    """Height of `text` wrapped to `width`, honouring explicit newlines."""
    glyph = (UPPER_GLYPH if upper else AVG_GLYPH) * size
    lines = 0
    for paragraph in text.split("\n"):
        if not paragraph:
            lines += 1
            continue
        lines += max(1, math.ceil(len(paragraph) * glyph / max(width, 1.0)))
    return lines * line_height(size)


def strings(source: str, key: str) -> list[str]:
    """Every double-quoted value of `key` in a GDScript data table."""
    return re.findall(rf'"{key}":\s*"((?:[^"\\]|\\.)*)"', source)


def main() -> int:
    problems: list[str] = []
    rows: list[str] = []

    card_db = read("scripts/cards/card_db.gd")
    site_db = read("scripts/sites/site_db.gd")
    hq = read("scripts/meta/headquarters.gd")
    game_manager = read("scripts/autoload/game_manager.gd")
    hud = read("scripts/ui/hud.gd")
    site_panel = read("scripts/ui/site_panel.gd")
    hq_panel = read("scripts/ui/headquarters_panel.gd")
    title = read("scripts/ui/title_screen.gd")

    # --- Policy Card buttons ------------------------------------------------
    # Up to four buttons share the row: three offers plus PATCH UP.
    card_panel_w, card_panel_h = panel_box("scenes/ui/hud.tscn", "CardPanel")
    card_row_width = card_panel_w - 40
    card_width = card_row_width / 4 - 12
    size = code_size(hud, "func _build_card_button")
    height = code_min_height(hud, "func _build_card_button")
    worst, worst_id = 0.0, ""
    for card_id, text in zip(strings(card_db, "id"), strings(card_db, "text")):
        title_line = max(strings(card_db, "title"), key=len)
        # title, blank, text, blank, "CATEGORY · RARITY"
        block = f"{title_line}\n\n{text}\n\nMONSTER MUNCH · UNCOMMON"
        needed = wrapped_height(block, card_width, size)
        if needed > worst:
            worst, worst_id = needed, card_id
    rows.append(f"  card panel {card_panel_w:.0f}x{card_panel_h:.0f}px")
    rows.append(f"  policy card button: {card_width:.0f}x{height:.0f}px at {size}px, "
                f"worst case needs {worst:.0f}px ({worst_id})")
    if worst * HEADROOM > height:
        problems.append(
            f"a Policy Card button is {height:.0f}px tall but '{worst_id}' needs "
            f"{worst:.0f}px at {size}px font — the text will clip")

    if height + 34 * 1.32 + 4 + 32 > card_panel_h:
        problems.append(
            f"card buttons are {height:.0f}px tall inside a {card_panel_h:.0f}px panel; "
            f"with the title and margins they do not fit the panel at all")

    # Exclusions carry two extra lines.
    excl = [t for i, t in zip(strings(card_db, "id"), strings(card_db, "text"))
            if i.startswith("excl_")]
    downsides = strings(card_db, "downside")
    if excl and downsides:
        block = (f"{max(strings(card_db, 'title'), key=len)}\n\n{max(excl, key=len)}\n\n"
                 f"EXCLUSION — {max(downsides, key=len)}\n\nCATASTROPHE · RARE")
        needed = wrapped_height(block, card_width, size)
        rows.append(f"  exclusion card (two extra lines): needs {needed:.0f}px")
        if needed * HEADROOM > height:
            problems.append(
                f"an Exclusion card needs {needed:.0f}px in a {height:.0f}px button")

    # --- Site option buttons ------------------------------------------------
    # Panel inset 96px each side of 1280, then 32px margins.
    site_width = 1280 - 192 - 64
    size = code_size(site_panel, "func _build_option_button")
    height = code_min_height(site_panel, "func _build_option_button")
    labels, details = strings(site_db, "label"), strings(site_db, "detail")
    block = f"{max(labels, key=len)}        999 PREMIUMS\n{max(details, key=len)}"
    needed = wrapped_height(block, site_width, size)
    rows.append(f"  site option: {site_width:.0f}x{height:.0f}px at {size}px, "
                f"worst case needs {needed:.0f}px")
    if needed * HEADROOM > height:
        problems.append(
            f"a site option button is {height:.0f}px tall but the longest option "
            f"needs {needed:.0f}px at {size}px")

    # --- Headquarters upgrade rows -----------------------------------------
    hq_width = 1280 - 128 - 56
    size = code_size(hq_panel, "func _build_upgrade_button")
    height = code_min_height(hq_panel, "func _build_upgrade_button")
    block = (f"{max(strings(hq, 'title'), key=len)}   [3/3]        999 FILES\n"
             f"{max(strings(hq, 'effect'), key=len)}\n"
             f"{max(strings(hq, 'blurb'), key=len)}")
    needed = wrapped_height(block, hq_width, size)
    rows.append(f"  HQ upgrade row: {hq_width:.0f}x{height:.0f}px at {size}px, "
                f"worst case needs {needed:.0f}px")
    if needed * HEADROOM > height:
        problems.append(
            f"an HQ upgrade row is {height:.0f}px tall but the longest upgrade "
            f"needs {needed:.0f}px at {size}px")

    # --- Deductible buttons -------------------------------------------------
    ded_width = 720
    size = code_size(title, "func _build_deductibles")
    height = code_min_height(title, "func _build_deductibles")
    block = (f"{max(strings(game_manager, 'label'), key=len)}\n"
             f"{max(strings(game_manager, 'blurb'), key=len)}\nStarting Coverage 130")
    needed = wrapped_height(block, ded_width, size)
    rows.append(f"  deductible button: {ded_width:.0f}x{height:.0f}px at {size}px, "
                f"worst case needs {needed:.0f}px")
    if needed * HEADROOM > height:
        problems.append(
            f"a deductible button is {height:.0f}px tall but the longest preset "
            f"needs {needed:.0f}px at {size}px")

    # --- The claim report ---------------------------------------------------
    # ClaimPanel is 560x380 (offsets -280..280, -190..190) minus 24/20 margins,
    # and the report is a fixed 13 lines plus the Case File tail.
    claim_size = int(re.search(
        r'\[node name="ClaimText".*?font_size = (\d+)',
        read("scenes/ui/hud.tscn"), re.DOTALL).group(1))
    claim_panel_w, claim_panel_h = panel_box("scenes/ui/hud.tscn", "ClaimPanel")
    # The longest report line, measured rather than guessed.
    longest_line = "Endorsements held:  8          Premiums collected:  9999"
    claim_body_width = claim_panel_w - 48
    claim_lines = 15
    claim_needed = claim_lines * line_height(claim_size)
    wrapped = wrapped_height("\n".join([longest_line] * claim_lines),
                             claim_body_width, claim_size)
    claim_needed = max(claim_needed, wrapped)
    claim_available = claim_panel_h - 40 - (34 * 1.32 + 4) - 70   # title + button
    rows.append(f"  claim report: {claim_body_width:.0f}x{claim_available:.0f}px of room "
                f"at {claim_size}px, {claim_lines} lines need {claim_needed:.0f}px")
    if claim_needed > claim_available:
        problems.append(
            f"the claim report needs {claim_needed:.0f}px for {claim_lines} lines at "
            f"{claim_size}px but the panel leaves {claim_available:.0f}px — it will clip")

    # --- Nothing may be small enough to be unreadable on a phone ------------
    smallest = 999
    where = ""
    for path in list((ROOT / "scenes").rglob("*.tscn")) + list((ROOT / "scripts").rglob("*.gd")):
        text = path.read_text(encoding="utf-8")
        for found in re.finditer(
                r'(?:theme_override_font_sizes/font_size = |add_theme_font_size_override\("font_size", )(\d+)',
                text):
            value = int(found.group(1))
            if value < smallest:
                smallest, where = value, f"{path.relative_to(ROOT)}:{text.count(chr(10), 0, found.start()) + 1}"
    rows.append(f"  smallest font in the project: {smallest}px ({where})")
    if smallest < 20:
        problems.append(
            f"{where} sets {smallest}px. Below 20px on this 1280x720 viewport is "
            f"the size the player already reported as unreadable")

    # --- nothing that carries text may be dimmed out of legibility ----------
    # The Claim Map shipped with unreachable nodes at
    #     modulate = Color(tint.r, tint.g, tint.b, 0.3)
    # modulate multiplies the WHOLE node -- the text and the dark outline the
    # theme puts behind it, not just the fill -- so on a near-black background
    # those labels were simply not there, and the player reported the map as an
    # empty screen. Card buttons, site options, HQ rows and map nodes are all
    # Buttons built in code and tinted this same way, so this is a class.
    #
    # Two things this gets right that the obvious version does not. It measures
    # the BRIGHTEST channel rather than luma, because on a dark background what
    # separates text from the background is any one channel being bright -- a
    # luma test flags the deliberate red damage flash in hud.gd, which is fine.
    # And it reads a trailing literal alpha even when the colour channels are
    # expressions, because that is exactly the form the real bug took.
    ALPHA_FLOOR = 0.6
    BRIGHTNESS_FLOOR = 0.5
    NUM = r"[-+]?[\d.]+"
    for path in sorted((ROOT / "scripts").rglob("*.gd")):
        text = path.read_text(encoding="utf-8")
        if ".text = " not in text and "add_theme_color_override" not in text:
            continue          # nothing in here draws type
        for found in re.finditer(r"modulate = Color\(([^()]*(?:\([^()]*\)[^()]*)*)\)",
                                 text):
            args = [a.strip() for a in found.group(1).split(",")]
            line = text.count("\n", 0, found.start()) + 1
            where = f"{path.relative_to(ROOT)}:{line}"
            if len(args) == 4 and re.fullmatch(NUM, args[3]):
                alpha = float(args[3])
                if alpha < ALPHA_FLOOR:
                    problems.append(
                        f"{where}: modulate sets alpha {alpha}, under "
                        f"{ALPHA_FLOOR}. modulate fades the node's TEXT and its "
                        f"outline too, so this makes the label itself "
                        f"unreadable on a dark background -- carry the state "
                        f"with add_theme_color_override(\"font_color\") and "
                        f"leave modulate alone")
                    continue
            if len(args) >= 3 and all(re.fullmatch(NUM, a) for a in args[:3]):
                alpha = float(args[3]) if len(args) == 4 and re.fullmatch(
                    NUM, args[3]) else 1.0
                brightest = max(float(a) for a in args[:3]) * alpha
                if brightest < BRIGHTNESS_FLOOR:
                    problems.append(
                        f"{where}: modulate leaves the brightest channel at "
                        f"{brightest:.2f}, under {BRIGHTNESS_FLOOR}. That dims "
                        f"the node's text as well as its fill")

    for row in rows:
        print(row)

    if problems:
        print("\nFAIL")
        for problem in problems:
            print(f" - {problem}")
        return 1

    print("\nEvery measured block fits, and nothing is under 20px.")
    return 0


if __name__ == "__main__":
    sys.exit(main())
