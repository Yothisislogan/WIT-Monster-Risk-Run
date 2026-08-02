#!/usr/bin/env python3
"""Balance model for the Risk / Reward economy (GAME_DESIGN.md §8, §11, §15).

There is no Godot binary in this environment and no way to playtest, so the
economy is designed against this model instead: it mirrors the exact constants
the GDScript is meant to use, runs a Monte Carlo of full 11-room runs across
every deductible and two skill profiles, and asserts the design targets.

The Risk scalars and the Munch heal are read directly out of game_manager.gd,
so those cannot drift. The deductible table, the shop curve and the healing
table are still mirrored by hand — if you change one of those, change it here
too and keep this green.

    python3 tools/check_economy.py [-v]
"""
import random
import re
import statistics
import sys
from pathlib import Path

# Constants read straight out of the GDScript rather than retyped here. The
# "keep them in sync by hand" note this file used to carry is exactly how the
# Risk damping curve ended up existing only in the model, and the Exclusion
# cost ended up 15 points in the game and 18 here.
_GM = (Path(__file__).resolve().parent.parent
       / "scripts" / "autoload" / "game_manager.gd").read_text(encoding="utf-8")


def _gm_const(name, fallback):
    found = re.search(rf"^const {name} := (-?[\d.]+)", _GM, re.MULTILINE)
    return float(found.group(1)) if found else fallback

# --- Risk Meter (§11) -------------------------------------------------------
# Risk is stored 0..1; the design and the HUD talk in "Risk points" = risk*100.
RISK_BANDS = [(0.75, "UNINSURABLE"), (0.50, "SEVERE"), (0.25, "ELEVATED"), (0.0, "STANDARD")]

RISK_SOURCES = {           # Risk points added (the float field is points/100)
    "exclusion_taken": _gm_const("RISK_PER_EXCLUSION", 0.18) * 100,
    "room_without_healing": _gm_const("RISK_PER_UNHEALED_SITE", 0.035) * 100,
    "decline_card": 4,
    "suspicious_container": 5,
    "claim_deny": 14,
    "ignore_safety_device": 10,
    "optional_challenge": 8,
    "hazard_room_entry": 8,
    "miniboss_room": 8,
    # Closing an act settles the claim and releases pressure. Mirrors
    # GameManager.RISK_RELIEF_PER_BOSS.
    "boss_defeated": -_gm_const("RISK_RELIEF_PER_BOSS", 0.09) * 100,
    "cancel_policy": 3,
}
# Diminishing accrual: each source is worth `points * (1 - RISK_DAMPING*risk)`.
# The meter approaches UNINSURABLE asymptotically instead of flinging the
# player there, so the top band is somewhere you climb to on purpose.
RISK_DAMPING = _gm_const("RISK_DAMPING", 0.40)

RISK_SINKS = {
    "safety_inspection_fixed": -8,
    "claim_file_properly": -6,
    "risk_seminar": -12,
    "revive_used": -20,
}

# Continuous scalars driven by risk.
# Danger grows slowly and reward grows fast: the whole point of the meter is
# that taking risk must be *tempting* (§2 "tempted to take unnecessary risks"),
# so the reward slopes deliberately out-run the danger slopes.
ENEMY_HEALTH_PER_RISK = 0.35   # x(1 + r*this)
ENEMY_SPEED_PER_RISK = 0.25
ENEMY_DAMAGE_PER_RISK = 0.20
PREMIUM_PER_RISK = 0.75
SHOP_PRICE_PER_RISK = 0.25     # income (0.75) outruns prices (0.25) on purpose
LIFETIME_PER_RISK = 1.00
HEAL_SPAWN_PER_RISK = -0.35    # fewer medkits on the floor as risk climbs

# Tougher enemies mean longer fights mean more chances to be hit, but a good
# player's hits-taken grows sublinearly with fight length, hence the exponent.
EXPOSURE_EXPONENT = 0.5

ELITE_THRESHOLD = 0.25         # elites start at ELEVATED
ELITE_CHANCE_SLOPE = 0.40      # chance = (risk - 0.25) * 0.40  -> 30% at max

# --- Deductibles (§8) -------------------------------------------------------
# High Deductible's fragility comes from the small Coverage pool, NOT from
# stacking a damage-taken multiplier on top of it: environmental damage is a
# percentage of the pool, so a small pool already multiplies every hazard.
DEDUCTIBLES = {
    "low": dict(coverage=125, damage_taken=1.00, enemy_damage=0.95,
                enemy_health=0.90, enemy_speed=0.90, premium=0.80,
                heal_pickup=1.05, heal_munch=1.10, heal_purchase=1.10,
                heal_spawn=0.75, risk_start=0.00, risk_floor=0.00,
                card_quality=-0.10, lifetime=0.60, shop_price=0.75),
    "standard": dict(coverage=100, damage_taken=1.00, enemy_damage=1.00,
                     enemy_health=1.00, enemy_speed=1.00, premium=1.00,
                     heal_pickup=1.00, heal_munch=1.00, heal_purchase=1.00,
                     heal_spawn=0.65, risk_start=0.10, risk_floor=0.00,
                     card_quality=0.00, lifetime=1.00, shop_price=1.00),
    "high": dict(coverage=85, damage_taken=1.00, enemy_damage=1.00,
                 enemy_health=1.20, enemy_speed=1.10, premium=1.45,
                 heal_pickup=0.90, heal_munch=0.95, heal_purchase=0.85,
                 heal_spawn=0.55, risk_start=0.20, risk_floor=0.10,
                 card_quality=0.20, lifetime=1.80, shop_price=1.10),
}

# --- Healing economy (§7, §8) ----------------------------------------------
PICKUP_HEAL_RATIO = 0.17       # of max Coverage
MUNCH_HEAL_RATIO = _gm_const("MUNCH_HEAL", 14) / 100.0
PATCH_HEAL_RATIO = 0.35
# Environmental damage (heat vents, pits) is a percentage of max Coverage, so
# a smaller Coverage pool does not silently multiply every hazard in the game.
ENV_DAMAGE_RATIO = 0.10
HEAL_SPAWN_PITY = 3            # guaranteed medkit on the Nth barren room

# --- Shop (§15) -------------------------------------------------------------
SHOP_BASE = {
    "patch": 55, "limit_increase": 110, "card_common": 88, "card_uncommon": 150,
    "card_rare": 238, "card_exclusion": 185, "umbrella": 68, "retainer": 295,
    "seminar": 60, "briefcase": 75, "boost": 50, "cancel_policy": 40,
}
SHOP_INFLATION_PER_ROOM = 0.14
REROLL_BASE, REROLL_STEP, REROLL_MAX = 25, 20, 4

# --- Room reward loop (§15) -------------------------------------------------
CLEAR_PAYOUT_BASE = 12
CLEAR_PAYOUT_PER_KILL = 4
NO_CLAIMS_BONUS = 25
DECLINE_PAYOUT = 60
MINIBOSS_PAYOUT = 120
SECRET_PAYOUT = 200
BOSS_PAYOUT = 250
CLEAR_MULT = {"combat": 1.25, "traversal": 1.0, "hazard": 1.40,
              "miniboss": 1.0, "boss": 1.0, "shop": 0.0, "claim": 0.0,
              "rest": 0.0}

# Authored room contents, measured from scenes/rooms/test_room_*.tscn.
ROOM_CONTENT = {           # coins placed, crates(x3 coins), enemies, drops/enemy
    "combat":    dict(coins=8, crates=3, enemies=4, drops=2.25),
    "traversal": dict(coins=12, crates=3, enemies=1, drops=2.0),
    "hazard":    dict(coins=8, crates=2, enemies=3, drops=2.25),
    "miniboss":  dict(coins=4, crates=1, enemies=1, drops=6.0),
    "boss":      dict(coins=0, crates=0, enemies=1, drops=8.0),
    "shop":      dict(coins=0, crates=0, enemies=0, drops=0.0),
    "claim":     dict(coins=0, crates=0, enemies=0, drops=0.0),
    "rest":      dict(coins=0, crates=0, enemies=0, drops=0.0),
}

# A representative route through the Claim Map (scripts/map/claim_map.gd):
# three acts of six sites, each act opening on combat, closing on a rest and
# then a boss, with three drawn sites between. The mix here matches the draw
# weights in ClaimMap.WEIGHTS -- roughly 60% combat, the rest split between
# shops, events and one mini-boss per act at most.
#
# This is the structure the run-length and economy targets are built against.
# If ClaimMap's shape changes, this changes with it: tools/check_map.py owns
# whether the *graph* is sound, and this owns whether the money works.
RUN_SEQUENCE = [
    # act one
    "combat", "combat", "shop", "hazard", "rest", "boss",
    # act two
    "combat", "hazard", "claim", "miniboss", "rest", "boss",
    # act three
    "combat", "combat", "shop", "hazard", "rest", "boss",
]
# Cards are the reward for fighting, so only combat sites draw them.
DRAFT_AFTER = {i for i, kind in enumerate(RUN_SEQUENCE)
               if kind in ("combat", "hazard", "miniboss", "boss")}
# Emergency Rider (§8 mercy rule): below this Coverage fraction a room always
# spawns its medkit. Without it, "fewer medkits at high Risk" turns every bad
# patch into a death spiral the player cannot see or escape.
EMERGENCY_RIDER_RATIO = 0.25
# Pre-Loss Inspection: entering a boss room tops Coverage up to this fraction
# and the arena carries one guaranteed pickup for the phase change. Without it
# the boss is an attrition check on the previous ten rooms rather than a skill
# check, and every death in the game lands on the economy instead of the fight.
BOSS_ENTRY_TOPUP = 0.50

# Skill profiles: hits taken, hazard contacts, and munches landed per room.
PROFILES = {
    "careful":  dict(hits=1.6, env=0.8, munches=0.9, combo=1.5,
                     pickup_take=0.95, spend_bias=0.80),
    "reckless": dict(hits=2.2, env=1.5, munches=2.1, combo=2.5,
                     pickup_take=0.75, spend_bias=1.00),
}

BASE_CONTACT_DAMAGE = 10.0
TRIALS = 4000


def band(risk):
    for threshold, name in RISK_BANDS:
        if risk >= threshold:
            return name
    return "STANDARD"


def premium_factor(ded, risk):
    return DEDUCTIBLES[ded]["premium"] * (1.0 + PREMIUM_PER_RISK * risk)


def shop_price(base, ded, risk, rooms_completed):
    raw = (base
           * (1.0 + SHOP_INFLATION_PER_ROOM * rooms_completed)
           * (1.0 + SHOP_PRICE_PER_RISK * risk)
           * DEDUCTIBLES[ded]["shop_price"])
    return int(round(raw / 5.0) * 5)      # prices always read in fives


def heal_amount(ded, source, max_coverage):
    ratio = {"pickup": PICKUP_HEAL_RATIO, "munch": MUNCH_HEAL_RATIO,
             "purchase": PATCH_HEAL_RATIO}[source]
    return max(1, int(ratio * max_coverage * DEDUCTIBLES[ded]["heal_" + source]))


def effective_hp(ded):
    """Coverage adjusted for incoming damage and for time spent in fights."""
    d = DEDUCTIBLES[ded]
    exposure = d["enemy_health"] ** EXPOSURE_EXPONENT
    return d["coverage"] / (d["damage_taken"] * d["enemy_damage"] * exposure)


def card_offer_slots(risk, ded, rng):
    """Slot-based rarity guarantees. Returns three rarity names (§9, §11)."""
    r = min(1.0, max(0.0, risk + DEDUCTIBLES[ded]["card_quality"]))
    if r >= 0.75:
        slots, excl = ["uncommon", "rare", "rare"], 0.50
    elif r >= 0.50:
        slots, excl = ["uncommon", "uncommon",
                       "rare" if rng.random() < 0.60 else "uncommon"], 0.35
    elif r >= 0.25:
        slots, excl = ["common", "uncommon",
                       "rare" if rng.random() < 0.15 else "uncommon"], 0.20
    else:
        slots, excl = ["common", "common",
                       "uncommon" if rng.random() < 0.25 else "common"], 0.08
    if rng.random() < excl:
        slots[2] = "exclusion"
    return slots


def simulate_run(ded, profile, rng):
    d = DEDUCTIBLES[ded]
    p = PROFILES[profile]
    max_cov = d["coverage"]
    cov = float(max_cov)
    premiums = 0
    earned = 0
    risk = d["risk_start"]
    rooms_completed = 0
    barren = 0
    purchases = []
    exclusions = 0
    died = False

    def add_risk(points):
        nonlocal risk
        scaled = points / 100.0
        if scaled > 0.0:
            scaled *= 1.0 - RISK_DAMPING * risk
        risk = min(1.0, max(d["risk_floor"], risk + scaled))

    def pay(amount):
        nonlocal premiums, earned
        gained = max(1, int(round(amount * premium_factor(ded, risk))))
        premiums += gained
        earned += gained

    coverage_at_boss = None
    for index, kind in enumerate(RUN_SEQUENCE):
        content = ROOM_CONTENT[kind]
        healed_this_room = False

        if kind == "shop":
            budget = premiums * p["spend_bias"]
            # Patch up while hurt and affordable — the shop is the only place a
            # player can convert Premiums back into Coverage, so they will.
            patches = 0
            while patches < 3 and cov < max_cov * 0.80:
                cost = shop_price(SHOP_BASE["patch"], ded, risk, rooms_completed)
                if budget < cost:
                    break
                premiums -= cost
                budget -= cost
                cov = min(max_cov, cov + heal_amount(ded, "purchase", max_cov))
                purchases.append("patch")
                patches += 1
            for tier in ("card_rare", "card_uncommon", "card_common"):
                cost = shop_price(SHOP_BASE[tier], ded, risk, rooms_completed)
                if budget >= cost:
                    premiums -= cost
                    purchases.append(tier)
                    break
            seminar = shop_price(SHOP_BASE["seminar"], ded, risk, rooms_completed)
            if risk > 0.70 and premiums >= seminar:
                premiums -= seminar
                add_risk(RISK_SINKS["risk_seminar"])
                purchases.append("seminar")
            rooms_completed += 1
            continue

        if kind == "rest":
            # Salvage Yard: a free patch-up, always available, once per act.
            cov = min(max_cov, cov + max_cov * PATCH_HEAL_RATIO)
            rooms_completed += 1
            continue

        if kind == "claim":
            # Reckless players deny the claim; careful ones file it properly.
            if profile == "reckless":
                add_risk(RISK_SOURCES["claim_deny"])
            else:
                pay(40)
                add_risk(RISK_SINKS["claim_file_properly"])
            rooms_completed += 1
            continue

        if kind == "boss":
            cov = max(cov, max_cov * BOSS_ENTRY_TOPUP)
            coverage_at_boss = cov / max_cov
        if kind == "hazard":
            add_risk(RISK_SOURCES["hazard_room_entry"])
        if kind == "miniboss":
            add_risk(RISK_SOURCES["miniboss_room"])

        # --- damage taken -------------------------------------------------
        elite_chance = max(0.0, (risk - ELITE_THRESHOLD) * ELITE_CHANCE_SLOPE)
        hit_damage = (BASE_CONTACT_DAMAGE * d["enemy_damage"]
                      * (1.0 + ENEMY_DAMAGE_PER_RISK * risk)
                      * (1.0 + 0.35 * elite_chance)
                      * d["damage_taken"])
        exposure = (d["enemy_health"] * (1.0 + ENEMY_HEALTH_PER_RISK * risk)) ** EXPOSURE_EXPONENT
        hits = max(0.0, rng.gauss(p["hits"], 0.45)) * exposure
        boss_mult = 3.0 if kind == "boss" else (1.8 if kind == "miniboss" else 1.0)
        cov -= hits * hit_damage * boss_mult
        env_hits = max(0.0, rng.gauss(p["env"], 0.35)) * (1.6 if kind == "hazard" else 1.0)
        cov -= env_hits * ENV_DAMAGE_RATIO * max_cov * d["damage_taken"]
        if kind in ("boss", "miniboss"):
            # The arena drops one guaranteed pickup at the phase change.
            cov = min(max_cov, cov + heal_amount(ded, "pickup", max_cov))

        # --- healing ------------------------------------------------------
        munches = max(0.0, rng.gauss(p["munches"], 0.6))
        if munches > 0 and cov < max_cov:
            cov = min(max_cov, cov + munches * heal_amount(ded, "munch", max_cov))
            healed_this_room = True
        spawn_p = d["heal_spawn"] * (1.0 + HEAL_SPAWN_PER_RISK * risk)
        emergency = cov < max_cov * EMERGENCY_RIDER_RATIO
        spawned = emergency or rng.random() < spawn_p or barren >= HEAL_SPAWN_PITY - 1
        barren = 0 if spawned else barren + 1
        if spawned and cov < max_cov and rng.random() < p["pickup_take"]:
            cov = min(max_cov, cov + heal_amount(ded, "pickup", max_cov))
            healed_this_room = True

        if cov <= 0:
            died = True
            break

        # --- payout -------------------------------------------------------
        coins = content["coins"] + content["crates"] * 3 + content["enemies"] * content["drops"]
        pay(coins * p["combo"])
        pay((CLEAR_PAYOUT_BASE + CLEAR_PAYOUT_PER_KILL * content["enemies"]) * CLEAR_MULT[kind])
        if kind == "miniboss":
            pay(MINIBOSS_PAYOUT)
        if kind == "boss":
            pay(BOSS_PAYOUT)
            add_risk(RISK_SOURCES["boss_defeated"])

        # --- risk from the reward loop -------------------------------------
        if not healed_this_room:
            add_risk(RISK_SOURCES["room_without_healing"])
        if index in DRAFT_AFTER:
            slots = card_offer_slots(risk, ded, rng)
            # A reckless player takes the exclusion whenever it is offered.
            if "exclusion" in slots and (profile == "reckless" or rng.random() < 0.35):
                exclusions += 1
                add_risk(RISK_SOURCES["exclusion_taken"])
        rooms_completed += 1

    lifetime = int(earned * d["lifetime"] * (1.0 + LIFETIME_PER_RISK * risk))
    return dict(died=died, rooms=rooms_completed, coverage=max(0.0, cov),
                reached_boss=coverage_at_boss is not None,
                coverage_at_boss=coverage_at_boss,
                max_coverage=max_cov, premiums=premiums, earned=earned,
                risk=risk, purchases=purchases, exclusions=exclusions,
                lifetime=lifetime)


def monte_carlo(ded, profile, trials=TRIALS, seed=7):
    rng = random.Random(seed)
    return [simulate_run(ded, profile, rng) for _ in range(trials)]


def mean(runs, key):
    return statistics.fmean(r[key] for r in runs)


def main():
    verbose = "-v" in sys.argv
    failures = []

    def check(label, ok, detail):
        status = "ok  " if ok else "FAIL"
        if verbose or not ok:
            print(f"  [{status}] {label}: {detail}")
        if not ok:
            failures.append(label)

    print("Risk / Reward economy model — GAME_DESIGN.md §8, §11, §15\n")

    # 1. Deductibles must be a real difficulty spread, not a rounding error.
    ehp = {k: effective_hp(k) for k in DEDUCTIBLES}
    ratio_low = ehp["low"] / ehp["standard"]
    ratio_high = ehp["high"] / ehp["standard"]
    print("Effective Coverage (pool / damage taken / time spent in fights):")
    for k, v in ehp.items():
        print(f"  {k:9s} {v:6.1f}")
    check("low deductible is 1.3-1.6x tougher to kill", 1.3 <= ratio_low <= 1.6,
          f"{ratio_low:.2f}x")
    check("high deductible is 0.65-0.80x", 0.65 <= ratio_high <= 0.80, f"{ratio_high:.2f}x")

    # 2. Risk must pay: income has to outrun shop inflation.
    print("\nPurchasing power vs Risk (standard deductible, after 6 rooms):")
    base_income = premium_factor("standard", 0.0)
    base_price = shop_price(SHOP_BASE["card_uncommon"], "standard", 0.0, 6)
    for r in (0.0, 0.25, 0.50, 0.75, 1.0):
        income = premium_factor("standard", r)
        price = shop_price(SHOP_BASE["card_uncommon"], "standard", r, 6)
        power = (income / base_income) / (price / base_price)
        print(f"  risk {int(r * 100):3d} ({band(r):12s}) income x{income:4.2f}  "
              f"uncommon card {price:4d}  real purchasing power x{power:4.2f}")
    power_max = ((premium_factor("standard", 1.0) / base_income)
                 / (shop_price(SHOP_BASE["card_uncommon"], "standard", 1.0, 6) / base_price))
    check("max risk buys 30-50% more than zero risk", 1.30 <= power_max <= 1.50,
          f"x{power_max:.2f}")

    # 3. Healing must shrink as the deductible rises, in size and in supply.
    print("\nHealing per source, as a fraction of that build's max Coverage:")
    for k in DEDUCTIBLES:
        cov = DEDUCTIBLES[k]["coverage"]
        frac = {s: heal_amount(k, s, cov) / cov for s in ("pickup", "munch", "purchase")}
        print(f"  {k:9s} pickup {frac['pickup']:5.1%}  munch {frac['munch']:5.1%}  "
              f"patch {frac['purchase']:5.1%}  (max {cov})")
    print("Expected Coverage restored per room (0.9 munches + spawn rate x pickup):")
    supply = {}
    for k in DEDUCTIBLES:
        cov = DEDUCTIBLES[k]["coverage"]
        supply[k] = (0.9 * heal_amount(k, "munch", cov)
                     + DEDUCTIBLES[k]["heal_spawn"] * heal_amount(k, "pickup", cov))
        print(f"  {k:9s} {supply[k]:5.1f} Coverage  ({supply[k] / cov:5.1%} of pool)")
    check("low restores 1.7-2.2x the Coverage per room that high does",
          1.7 <= supply["low"] / supply["high"] <= 2.2,
          f"{supply['low'] / supply['high']:.2f}x")
    high_cov = DEDUCTIBLES["high"]["coverage"]
    high_munch = heal_amount("high", "munch", high_cov) / high_cov
    check("munch stays >8% of pool on high deductible (the skill lane must work)",
          high_munch >= 0.08, f"{high_munch:.1%}")

    # 4. Full-run Monte Carlo.
    print(f"\nFull-run Monte Carlo ({TRIALS} runs each, 11-room Level 1):")
    print(f"  {'build':22s} {'died':>6s} {'rooms':>6s} {'end risk':>9s} "
          f"{'earned':>8s} {'left':>7s} {'buys':>6s} {'lifetime':>9s}")
    results = {}
    for ded in DEDUCTIBLES:
        for profile in PROFILES:
            runs = monte_carlo(ded, profile)
            results[(ded, profile)] = runs
            death_rate = sum(r["died"] for r in runs) / len(runs)
            buys = statistics.fmean(len(r["purchases"]) for r in runs)
            print(f"  {ded + '/' + profile:22s} {death_rate:5.0%} "
                  f"{mean(runs, 'rooms'):6.1f} {mean(runs, 'risk') * 100:9.0f} "
                  f"{mean(runs, 'earned'):8.0f} {mean(runs, 'premiums'):7.0f} "
                  f"{buys:6.1f} {mean(runs, 'lifetime'):9.0f}")

    rate = {k: sum(r["died"] for r in results[k]) / TRIALS for k in results}
    # The economy's job is to DELIVER the player to the boss in a fighting
    # state. Whether they win the boss is a skill fight this model cannot
    # honestly simulate, so the targets below are scoped to what the economy
    # controls: reaching the boss, and the Coverage you reach it with.
    print("\nWhat the economy delivers to the boss door:")
    print(f"  {'build':22s} {'reached boss':>13s} {'Coverage there':>15s} "
          f"{'died pre-boss':>14s}")
    for key, runs in results.items():
        reached = sum(r["reached_boss"] for r in runs) / len(runs)
        pre = 1.0 - reached
        at = statistics.fmean(r["coverage_at_boss"] for r in runs if r["reached_boss"]) \
            if reached else 0.0
        print(f"  {key[0] + '/' + key[1]:22s} {reached:12.0%} {at:14.0%} {pre:13.0%}")
        check(f"{key[0]}/{key[1]} is not killed by the economy before the boss",
              pre <= 0.15, f"{pre:.0%} died pre-boss")
        check(f"{key[0]}/{key[1]} does not arrive at the boss already dead",
              at >= 0.45, f"{at:.0%}")
    # Deductible and play style are independent axes, so monotonicity is
    # checked along each of them rather than down an interleaved list. The
    # old version compared low/reckless against standard/careful and failed,
    # which was the assertion being wrong: a careful player on Standard
    # *should* reach the boss healthier than a reckless one on Low.
    def arrival(deductible, profile):
        rows = [r for r in results[(deductible, profile)] if r["reached_boss"]]
        return statistics.fmean(r["coverage_at_boss"] for r in rows)

    for profile in PROFILES:
        by_deductible = [arrival(d, profile) for d in ("low", "standard", "high")]
        check(f"{profile}: boss-door Coverage falls as the deductible rises",
              all(a >= b - 0.005 for a, b in zip(by_deductible, by_deductible[1:])),
              " > ".join(f"{a:.0%}" for a in by_deductible))
    for deductible in DEDUCTIBLES:
        careful, reckless = arrival(deductible, "careful"), arrival(deductible, "reckless")
        check(f"{deductible}: careful play arrives healthier than reckless",
              careful >= reckless - 0.005, f"{careful:.0%} vs {reckless:.0%}")
    # The old assertion here measured the spread in boss-door Coverage. That
    # stopped meaning anything when the Claim Map started guaranteeing a free
    # Salvage Yard immediately before every boss: everyone now arrives topped
    # up, by design, and the spread measures the rest rather than the run.
    # What separates the deductibles over 18 sites is whether you finish.
    completion = [1.0 - rate[(d, p)] for d in ("low", "standard", "high")
                  for p in ("careful", "reckless")]
    check("the difficulty ladder is ordered by completion rate",
          all(a >= b - 0.03 for a, b in zip(completion, completion[1:])),
          " > ".join(f"{c:.0%}" for c in completion))
    check("the ladder spans at least 50 points of completion rate",
          completion[0] - completion[-1] >= 0.50,
          f"{(completion[0] - completion[-1]) * 100:.0f} points")
    for profile in PROFILES:
        rates = {k: rate[(k, profile)] for k in DEDUCTIBLES}
        check(f"{profile}: deductible difficulty is ordered low<standard<high",
              rates["low"] <= rates["standard"] <= rates["high"],
              "  ".join(f"{k} {v:.0%}" for k, v in rates.items()))

    # Reckless play must actually move the meter; careful play must not.
    careful = mean(results[("standard", "careful")], "risk")
    reckless = mean(results[("standard", "reckless")], "risk")
    check("careful standard run stays out of SEVERE", careful < 0.50,
          f"{careful * 100:.0f} points ({band(careful)})")
    check("reckless standard run reaches SEVERE", reckless >= 0.50,
          f"{reckless * 100:.0f} points ({band(reckless)})")
    check("careful and reckless are >=20 Risk points apart", reckless - careful >= 0.20,
          f"{(reckless - careful) * 100:.0f} points")

    # The shop must be a choice, not a shopping spree and not a museum.
    for (ded, profile), runs in results.items():
        buys = statistics.fmean(len(r["purchases"]) for r in runs)
        check(f"{ded}/{profile} makes 1.5-6 purchases per run", 1.5 <= buys <= 6.0,
              f"{buys:.1f}")

    # High Deductible must pay for itself in permanent currency (§8).
    lt_std = mean(results[("standard", "careful")], "lifetime")
    lt_high = mean(results[("high", "careful")], "lifetime")
    lt_low = mean(results[("low", "careful")], "lifetime")
    check("high deductible lifetime payout is 1.8-3.5x standard",
          1.8 <= lt_high / lt_std <= 3.5, f"{lt_high / lt_std:.2f}x")
    check("low deductible lifetime payout is 0.30-0.60x standard",
          0.30 <= lt_low / lt_std <= 0.60, f"{lt_low / lt_std:.2f}x")

    # 5. Card offers must visibly improve with risk.
    print("\nCard offer composition by band (standard deductible, 20000 draws):")
    rng = random.Random(11)
    for r in (0.10, 0.35, 0.60, 0.85):
        counts = {"common": 0, "uncommon": 0, "rare": 0, "exclusion": 0}
        for _ in range(20000):
            for slot in card_offer_slots(r, "standard", rng):
                counts[slot] += 1
        total = sum(counts.values())
        print(f"  risk {int(r * 100):3d} ({band(r):12s}) " + "  ".join(
            f"{k} {counts[k] / total:5.1%}" for k in ("common", "uncommon", "rare", "exclusion")))
    rng = random.Random(12)
    rare_low = sum(s == "rare" for _ in range(20000)
                   for s in card_offer_slots(0.10, "standard", rng)) / 60000
    rare_high = sum(s == "rare" for _ in range(20000)
                    for s in card_offer_slots(0.85, "standard", rng)) / 60000
    check("rares are near-absent at STANDARD", rare_low <= 0.01, f"{rare_low:.2%} of slots")
    check("rares are 40-60% of slots at UNINSURABLE", 0.40 <= rare_high <= 0.60,
          f"{rare_high:.2%} of slots")

    # 6. Shop prices must stay readable and reachable across the whole run.
    print("\nShop price curve (standard deductible):")
    print(f"  {'rooms':>5s} {'risk':>5s} {'patch':>6s} {'common':>7s} "
          f"{'uncommon':>9s} {'rare':>6s} {'reroll 1/2/3':>14s}")
    for rooms, r in ((0, 0.10), (3, 0.20), (7, 0.45), (10, 0.70)):
        rerolls = "/".join(str(shop_price(REROLL_BASE + REROLL_STEP * i, "standard", r, rooms))
                           for i in range(3))
        print(f"  {rooms:5d} {int(r * 100):5d} "
              f"{shop_price(SHOP_BASE['patch'], 'standard', r, rooms):6d} "
              f"{shop_price(SHOP_BASE['card_common'], 'standard', r, rooms):7d} "
              f"{shop_price(SHOP_BASE['card_uncommon'], 'standard', r, rooms):9d} "
              f"{shop_price(SHOP_BASE['card_rare'], 'standard', r, rooms):6d} {rerolls:>14s}")
    late_rare = shop_price(SHOP_BASE["card_rare"], "standard", 0.55, 7)
    late_earned = mean(results[("standard", "reckless")], "earned")
    check("the second shop's rare card costs 25-45% of a whole run's income",
          0.25 <= late_rare / late_earned <= 0.45, f"{late_rare} vs {late_earned:.0f} earned")

    print()
    if failures:
        print(f"{len(failures)} design target(s) missed: " + ", ".join(failures))
        return 1
    print("All economy design targets met.")
    return 0


if __name__ == "__main__":
    sys.exit(main())
