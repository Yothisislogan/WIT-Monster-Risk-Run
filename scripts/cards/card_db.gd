class_name CardDb
extends RefCounted
## The Policy Card catalogue (GAME_DESIGN.md §9, §10).
##
## Cards are authored here as plain data. To add one, append a dictionary —
## no core system needs to change. Every stat referenced below is consumed by
## GameManager.stat()/GameManager.factor(), so a typo is inert rather than fatal.
##
## Stats currently honoured:
##   damage_mult, fire_rate_mult, move_speed_mult, jump_mult, dash_cooldown_mult,
##   ability_cost_mult, premium_mult, coin_magnet_mult, burn_mult,
##   air_jumps, max_coverage, stomp_damage, pound_damage, munch_heal,
##   revives, shield_per_room, combo_window, invuln_time, charge_speed_mult

const CARDS := [
	# --- Attack -----------------------------------------------------------
	{"id": "actuarial_aim", "title": "Actuarial Aim", "category": "Attack",
	 "text": "Shots hit 25% harder. The numbers do not lie.",
	 "mults": {"damage_mult": 1.25}},
	{"id": "rapid_processing", "title": "Rapid Processing", "category": "Attack",
	 "text": "Fire 20% faster. Claims wait for no one.",
	 "mults": {"fire_rate_mult": 0.8}},
	{"id": "expedited_review", "title": "Expedited Review", "category": "Attack",
	 "rarity": PolicyCard.Rarity.UNCOMMON,
	 "text": "Charged shots build twice as fast.",
	 "mults": {"charge_speed_mult": 2.0}},
	{"id": "subrogation", "title": "Subrogation", "category": "Attack",
	 "rarity": PolicyCard.Rarity.UNCOMMON,
	 "text": "Stomping deals +20 damage. Recover costs from the responsible party.",
	 "mods": {"stomp_damage": 20}},
	{"id": "total_loss", "title": "Total Loss", "category": "Attack",
	 "rarity": PolicyCard.Rarity.RARE,
	 "text": "Ground pound shockwaves deal +45 damage.",
	 "mods": {"pound_damage": 45}},
	{"id": "accelerant", "title": "Accelerant Clause", "category": "Attack",
	 "rarity": PolicyCard.Rarity.UNCOMMON,
	 "text": "Flame Draft burns twice as hot.",
	 "mults": {"burn_mult": 2.0}},

	# --- Defense ----------------------------------------------------------
	{"id": "increased_limits", "title": "Increased Limits", "category": "Defense",
	 "text": "+25 maximum Coverage.",
	 "mods": {"max_coverage": 25}},
	{"id": "umbrella_policy", "title": "Umbrella Policy", "category": "Defense",
	 "rarity": PolicyCard.Rarity.UNCOMMON,
	 "text": "Start every room with a shield that blocks one hit.",
	 "mods": {"shield_per_room": 1}, "max_stacks": 1},
	{"id": "replacement_cost", "title": "Replacement Cost", "category": "Defense",
	 "rarity": PolicyCard.Rarity.RARE,
	 "text": "Revive once at half Coverage. Depreciation not applied.",
	 "mods": {"revives": 1}, "max_stacks": 2},
	{"id": "grace_period", "title": "Grace Period", "category": "Defense",
	 "text": "Invulnerability after a hit lasts 0.4s longer.",
	 "mods": {"invuln_time": 0.4}},

	# --- Movement ---------------------------------------------------------
	{"id": "rocket_boots", "title": "Rocket Boots", "category": "Movement",
	 "rarity": PolicyCard.Rarity.RARE,
	 "text": "Gain an extra mid-air jump.",
	 "mods": {"air_jumps": 1}, "max_stacks": 2},
	{"id": "no_claims_bonus", "title": "No-Claims Bonus", "category": "Movement",
	 "text": "Move 12% faster.",
	 "mults": {"move_speed_mult": 1.12}},
	{"id": "spring_loaded", "title": "Spring-Loaded Liability", "category": "Movement",
	 "text": "Jump 10% higher.",
	 "mults": {"jump_mult": 1.1}},
	{"id": "roadside_assist", "title": "Roadside Assistance", "category": "Movement",
	 "rarity": PolicyCard.Rarity.UNCOMMON,
	 "text": "Dash recovers 35% faster.",
	 "mults": {"dash_cooldown_mult": 0.65}},

	# --- Monster Munch ----------------------------------------------------
	{"id": "balanced_diet", "title": "Balanced Diet Rider", "category": "Monster Munch",
	 "text": "Munching restores 12 more Coverage.",
	 "mods": {"munch_heal": 12}},
	{"id": "loss_adjustment", "title": "Loss Adjustment", "category": "Monster Munch",
	 "rarity": PolicyCard.Rarity.UNCOMMON,
	 "text": "Enemies become munchable at 65% Coverage instead of 40%.",
	 "mods": {"weaken_ratio": 0.25}},

	# --- Boss ability -----------------------------------------------------
	{"id": "aggressive_adjusting", "title": "Aggressive Adjusting", "category": "Boss ability",
	 "text": "Flame Draft costs 30% less energy.",
	 "mults": {"ability_cost_mult": 0.7}},

	# --- Economy ----------------------------------------------------------
	{"id": "multi_policy", "title": "Multi-Policy Discount", "category": "Economy",
	 "text": "Premiums are worth 40% more.",
	 "mults": {"premium_mult": 1.4}},
	{"id": "direct_deposit", "title": "Direct Deposit", "category": "Economy",
	 "text": "Premiums are pulled in from much further away.",
	 "mults": {"coin_magnet_mult": 2.2}},
	{"id": "claims_free", "title": "Claims-Free Discount", "category": "Economy",
	 "rarity": PolicyCard.Rarity.UNCOMMON,
	 "text": "Your Adjuster's Streak lasts 2 seconds longer.",
	 "mods": {"combo_window": 2.0}},

	# --- Exclusions (§10): real upside, disclosed downside -----------------
	{"id": "excl_high_deductible", "title": "Hazardous Materials Rider", "category": "Catastrophe",
	 "rarity": PolicyCard.Rarity.RARE, "is_exclusion": true,
	 "text": "Deal 60% more damage.",
	 "downside": "Your maximum Coverage is cut by 30.",
	 "mults": {"damage_mult": 1.6}, "mods": {"max_coverage": -30}, "max_stacks": 1},
	{"id": "excl_actual_cash", "title": "Actual Cash Value", "category": "Economy",
	 "rarity": PolicyCard.Rarity.UNCOMMON, "is_exclusion": true,
	 "text": "Premiums are worth double.",
	 "downside": "Munching restores 8 less Coverage.",
	 "mults": {"premium_mult": 2.0}, "mods": {"munch_heal": -8}, "max_stacks": 1},
	{"id": "excl_glass_cannon", "title": "Fragile Goods Endorsement", "category": "Catastrophe",
	 "rarity": PolicyCard.Rarity.RARE, "is_exclusion": true,
	 "text": "Move 25% faster and fire 35% faster.",
	 "downside": "Invulnerability after a hit is halved.",
	 "mults": {"move_speed_mult": 1.25, "fire_rate_mult": 0.65},
	 "mods": {"invuln_time": -0.4}, "max_stacks": 1},
	{"id": "excl_lapsed", "title": "Lapsed Coverage", "category": "Catastrophe",
	 "rarity": PolicyCard.Rarity.UNCOMMON, "is_exclusion": true,
	 "text": "Gain an extra mid-air jump and dash twice as often.",
	 "downside": "Start each room with 10 less Coverage.",
	 "mods": {"air_jumps": 1, "room_entry_damage": 10},
	 "mults": {"dash_cooldown_mult": 0.5}, "max_stacks": 1},
]

const _POOL_CACHE_KEY := "cards"


static func all() -> Array:
	var out: Array = []
	for data in CARDS:
		out.append(PolicyCard.make(data))
	return out


static func by_id(id: String) -> PolicyCard:
	for data in CARDS:
		if String(data.get("id", "")) == id:
			return PolicyCard.make(data)
	return null


## Draw `count` distinct offers the player can still take. `risk` biases the
## roll toward rarer cards and exclusions — taking risks pays out (§11).
static func draw_offers(count: int, held: Dictionary, risk: float, rng: RandomNumberGenerator) -> Array:
	var candidates: Array = []
	for data in CARDS:
		var card := PolicyCard.make(data)
		if int(held.get(card.id, 0)) >= card.max_stacks:
			continue
		candidates.append(card)
	if candidates.is_empty():
		return []

	var picks: Array = []
	for i in mini(count, candidates.size()):
		var total := 0.0
		for card in candidates:
			total += _weight(card, risk)
		var roll := rng.randf() * total
		var chosen: PolicyCard = candidates[0]
		for card in candidates:
			roll -= _weight(card, risk)
			if roll <= 0.0:
				chosen = card
				break
		picks.append(chosen)
		candidates.erase(chosen)
	return picks


static func _weight(card: PolicyCard, risk: float) -> float:
	var weight := 1.0
	match card.rarity:
		PolicyCard.Rarity.UNCOMMON:
			weight = 0.55 + risk * 0.5
		PolicyCard.Rarity.RARE:
			weight = 0.18 + risk * 0.7
		_:
			weight = 1.0
	if card.is_exclusion:
		# Exclusions barely show up while playing safe, and crowd the offers
		# once the Risk Meter is high.
		weight *= 0.35 + risk * 1.6
	return maxf(weight, 0.02)
