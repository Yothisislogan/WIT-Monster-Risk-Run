class_name SiteDb
extends RefCounted
## Content for the Claim Map's non-combat sites (GAME_DESIGN.md §15, §19).
##
## Every site — the shop, the rest, the events — is the same screen: a title,
## some prose, and a list of options. So all three are just option lists, and
## adding content is adding a dictionary entry rather than a new panel (§29).
##
## An option is:
##   {"label", "detail", "cost": int, "effect": {...}}
## and every effect goes through apply(), which returns the line the panel
## prints back at you. Effects are data rather than Callables so the whole
## table stays inspectable by tools/check_sites.py.

const HEAL_RATIO := 0.35
const STRIP_PREMIUMS := 55
const STRIP_RISK := 0.08

## Shop prices by rarity index (common, uncommon, rare).
const CARD_PRICES := [70, 125, 195]
const PATCH_COST := 55
const PATCH_HEAL := 45
const UMBRELLA_COST := 90
const EXCLUSION_REMOVAL_COST := 110


# --- Option lists -----------------------------------------------------------

static func options_for(kind: int, rng: RandomNumberGenerator) -> Dictionary:
	match kind:
		ClaimMap.Kind.SALVAGE:
			return _salvage()
		ClaimMap.Kind.OFFICE:
			return _office(rng)
		_:
			return _claim_event(rng)


static func _salvage() -> Dictionary:
	var options: Array = [
		{"label": "PATCH UP",
		 "detail": "Restore %d%% of your Coverage. No forms." % int(HEAL_RATIO * 100.0),
		 "cost": 0, "effect": {"kind": "heal_ratio", "value": HEAL_RATIO}},
		{"label": "STRIP FOR PARTS",
		 "detail": "Take %d Premiums off the site. Technically it is still an active claim." % STRIP_PREMIUMS,
		 "cost": 0, "effect": {"kind": "premiums", "value": STRIP_PREMIUMS,
				"risk": STRIP_RISK}},
	]
	if GameManager.exclusion_count() > 0:
		options.append({
			"label": "RE-READ THE POLICY",
			"detail": "Strike out one Exclusion. Takes the whole rest to do it.",
			"cost": 0, "effect": {"kind": "remove_exclusion"}})
	return {
		"title": "SALVAGE YARD",
		"prose": "Nobody has been out here in years. The gate was already open, which "
				+ "you will be describing later as \"unsecured\".",
		"options": options,
	}


static func _office(rng: RandomNumberGenerator) -> Dictionary:
	var options: Array = []
	for card in CardDb.draw_offers(2, GameManager.held_cards, GameManager.risk, rng):
		var price := int(CARD_PRICES[clampi(card.rarity, 0, CARD_PRICES.size() - 1)])
		options.append({
			"label": card.title.to_upper(),
			"detail": "%s\n%s · %s" % [card.text, card.category.to_upper(), card.rarity_name()],
			"cost": price,
			"effect": {"kind": "card", "value": card.id}})
	options.append({
		"label": "COVERAGE PATCH",
		"detail": "Restore %d Coverage. Adhesive, mostly." % PATCH_HEAL,
		"cost": PATCH_COST, "effect": {"kind": "heal", "value": PATCH_HEAL}})
	if not GameManager.umbrella_active:
		options.append({
			"label": "UMBRELLA COVERAGE",
			"detail": "Blocks the next hit outright. Sold as-is.",
			"cost": UMBRELLA_COST, "effect": {"kind": "umbrella"}})
	if GameManager.exclusion_count() > 0:
		options.append({
			"label": "BUY OUT AN EXCLUSION",
			"detail": "Remove one Exclusion from your policy. The adjuster does not make eye contact.",
			"cost": EXCLUSION_REMOVAL_COST, "effect": {"kind": "remove_exclusion"}})
	return {
		"title": "ADJUSTER'S OFFICE",
		"prose": "A folding table, a laminated price list, and a man who has "
				+ "already decided how this ends.",
		"options": options,
	}


# --- Claim Events -----------------------------------------------------------
## §19's humour, made playable: each one is a real decision with a real cost,
## and the joke is that the correct answer is always the one that generates
## more paperwork for somebody else.

const EVENTS := [
	{
		"title": "ACT OF DOG",
		"prose": "A claimant states that a neighbour's dog ate their roof. The dog is "
				+ "present. The dog is enormous. The dog is, on inspection, insured.",
		"options": [
			{"label": "PAY THE CLAIM", "detail": "It is a covered peril if you squint.",
			 "cost": 45, "effect": {"kind": "risk", "value": -0.1}},
			{"label": "DENY THE CLAIM", "detail": "Cite the exclusion for large dogs.",
			 "cost": 0, "effect": {"kind": "premiums", "value": 70, "risk": 0.12}},
			{"label": "RECRUIT THE DOG", "detail": "It clearly knows what it is doing.",
			 "cost": 0, "effect": {"kind": "umbrella"}},
		],
	},
	{
		"title": "THE PAPERWORK",
		"prose": "Four hundred pages of forms, in triplicate, describing damage you "
				+ "personally caused eleven minutes ago.",
		"options": [
			{"label": "FILE IT PROPERLY", "detail": "Takes time. Lowers your assessed Risk.",
			 "cost": 0, "effect": {"kind": "risk", "value": -0.14}},
			{"label": "EAT THE PAPERWORK", "detail": "No forms, no claim. Nutritious.",
			 "cost": 0, "effect": {"kind": "heal", "value": 30, "risk": 0.1}},
			{"label": "FORWARD IT TO LEGAL", "detail": "Somebody else's quarter now.",
			 "cost": 0, "effect": {"kind": "premiums", "value": 40}},
		],
	},
	{
		"title": "PRE-EXISTING CONDITION",
		"prose": "The building was already on fire when the policy was written. Everyone "
				+ "agrees on this. Nobody agrees on what it means.",
		"options": [
			{"label": "HONOUR THE POLICY", "detail": "Expensive. Reputable.",
			 "cost": 80, "effect": {"kind": "max_coverage", "value": 12}},
			{"label": "INVOKE THE CLAUSE", "detail": "There is always a clause.",
			 "cost": 0, "effect": {"kind": "premiums", "value": 95, "risk": 0.15}},
		],
	},
	{
		"title": "UNATTENDED VEHICLE",
		"prose": "A car, keys in the ignition, engine running, parked across two "
				+ "spaces and one hydrant. The owner is nowhere. The claim is pre-filled.",
		"options": [
			{"label": "SECURE THE VEHICLE", "detail": "Do the responsible thing.",
			 "cost": 0, "effect": {"kind": "risk", "value": -0.08}},
			{"label": "STRIP IT", "detail": "It was going to be a total loss anyway.",
			 "cost": 0, "effect": {"kind": "premiums", "value": 85, "risk": 0.16}},
			{"label": "EAT THE VEHICLE", "detail": "Removes the vehicle. And the claim.",
			 "cost": 0, "effect": {"kind": "heal", "value": 45, "risk": 0.1}},
		],
	},
	{
		"title": "THE INSPECTOR",
		"prose": "A site inspector wants a word about the last four Risk Zones. He has "
				+ "photographs. Several of them feature you mid-air.",
		"options": [
			{"label": "COOPERATE FULLY", "detail": "Hand over everything. Feel lighter.",
			 "cost": 0, "effect": {"kind": "risk", "value": -0.18}},
			{"label": "OFFER A GOODWILL PAYMENT", "detail": "Not a bribe. A gesture.",
			 "cost": 70, "effect": {"kind": "risk", "value": -0.05}},
			{"label": "BE VERY LARGE AT HIM", "detail": "He is only human.",
			 "cost": 0, "effect": {"kind": "premiums", "value": 60, "risk": 0.14}},
		],
	},
	{
		"title": "MOULD DISCOVERY",
		"prose": "Something is growing behind the drywall. It is green, it is spreading, "
				+ "and it has filed a claim of its own.",
		"options": [
			{"label": "REMEDIATE", "detail": "Costly, thorough, correct.",
			 "cost": 65, "effect": {"kind": "heal_ratio", "value": 0.3}},
			{"label": "PAINT OVER IT", "detail": "Out of sight, out of policy.",
			 "cost": 0, "effect": {"kind": "premiums", "value": 50, "risk": 0.12}},
			{"label": "EAT THE MOULD", "detail": "You have eaten worse. Recently.",
			 "cost": 0, "effect": {"kind": "damage", "value": 12, "heal_after": 0}},
		],
	},
	{
		"title": "PREMIUM AUDIT",
		"prose": "Head office has noticed how much you have been collecting and would "
				+ "like to understand your methodology.",
		"options": [
			{"label": "SUBMIT THE FIGURES", "detail": "They will find what they find.",
			 "cost": 0, "effect": {"kind": "risk", "value": -0.12}},
			{"label": "ROUND DOWN", "detail": "Give some back. Look humble.",
			 "cost": 60, "effect": {"kind": "max_coverage", "value": 10}},
			{"label": "DECLINE TO PARTICIPATE", "detail": "Audits are voluntary if you are big enough.",
			 "cost": 0, "effect": {"kind": "premiums", "value": 75, "risk": 0.15}},
		],
	},
	{
		"title": "A GENUINELY NICE FAMILY",
		"prose": "Their house is gone. They are being lovely about it. One of them offers "
				+ "you a biscuit while you take the photographs.",
		"options": [
			{"label": "PAY OUT IN FULL", "detail": "Every penny. Immediately.",
			 "cost": 110, "effect": {"kind": "max_coverage", "value": 18, "risk": -0.1}},
			{"label": "PAY THE MINIMUM", "detail": "The policy is the policy.",
			 "cost": 35, "effect": {"kind": "premiums", "value": 25}},
			{"label": "TAKE THE BISCUIT AND GO", "detail": "You are not proud of this one.",
			 "cost": 0, "effect": {"kind": "heal", "value": 8, "risk": 0.2}},
		],
	},
]


static func _claim_event(rng: RandomNumberGenerator) -> Dictionary:
	var event: Dictionary = EVENTS[rng.randi_range(0, EVENTS.size() - 1)]
	return {
		"title": String(event["title"]),
		"prose": String(event["prose"]),
		"options": (event["options"] as Array).duplicate(true),
	}


# --- Effects ----------------------------------------------------------------

## Applies one option and returns the line the panel shows back. Every branch
## returns something: a site that silently does nothing reads as a bug.
static func apply(option: Dictionary) -> String:
	var cost := int(option.get("cost", 0))
	if cost > 0 and not GameManager.spend_currency(cost):
		return "Declined for insufficient Premiums."
	var effect: Dictionary = option.get("effect", {})
	var lines: Array[String] = []

	match String(effect.get("kind", "")):
		"heal":
			GameManager.heal(int(effect.get("value", 0)))
			lines.append("Coverage restored.")
		"heal_ratio":
			GameManager.heal(int(round(float(GameManager.max_coverage)
					* float(effect.get("value", 0.0)))))
			lines.append("Coverage restored.")
		"premiums":
			GameManager.add_premiums_flat(int(effect.get("value", 0)))
			lines.append("Premiums collected.")
		"umbrella":
			GameManager.grant_umbrella()
			lines.append("Umbrella Coverage attached.")
		"card":
			GameManager.add_card(String(effect.get("value", "")))
			lines.append("Endorsement added to your policy.")
		"remove_exclusion":
			var removed := GameManager.remove_one_exclusion()
			lines.append("%s struck from the policy." % removed if removed != ""
					else "No Exclusions on file.")
		"max_coverage":
			GameManager.add_max_coverage(int(effect.get("value", 0)))
			lines.append("Policy limit raised.")
		"damage":
			GameManager.damage(int(effect.get("value", 0)), "an unwise decision on site")
			lines.append("That had a cost.")
		"risk":
			lines.append(_risk_line(float(effect.get("value", 0.0))))
			GameManager.add_risk(float(effect.get("value", 0.0)))
		_:
			lines.append("Noted for the file.")

	# A secondary risk swing rides along with most effects: it is the price of
	# the option rather than the option itself.
	if effect.has("risk"):
		GameManager.add_risk(float(effect["risk"]))
		lines.append(_risk_line(float(effect["risk"])))
	return " ".join(lines)


static func _risk_line(amount: float) -> String:
	return "Risk assessment %s." % ("lowered" if amount < 0.0 else "raised")


## Whether an option can be taken right now, so the panel can grey it out
## rather than letting a player spend a tap discovering they cannot afford it.
static func affordable(option: Dictionary) -> bool:
	return GameManager.currency >= int(option.get("cost", 0))
