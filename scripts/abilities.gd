class_name Abilities
extends RefCounted
## Boss abilities absorbed from defeated bosses (GAME_DESIGN.md §12) and the
## combinations they form when you hold more than one (§14).
##
## Data only: the player controller asks which ability is equipped and what
## its combo is, and never hard-codes a list.
##
## Seven bosses, seven absorbed powers, plus Flame Draft to start with. Every
## one of the 28 pairs has a combination, because tools/check_bosses.py fails
## on a missing pair — a pair with no entry is invisible in play, and the
## player cannot tell an intentional gap from an oversight.

const FLAME_DRAFT := "flame_draft"
const IMPACT_DASH := "impact_dash"
const RISK_POOL := "risk_pool"
const UNDERTOW := "undertow"
const CLAUSE_BREAKER := "clause_breaker"
const SALVAGE_HOOK := "salvage_hook"
const MASS_CLAIM := "mass_claim"
const UNDERWRITE := "underwrite"

const ABILITIES := {
	FLAME_DRAFT: {
		"name": "FLAME DRAFT",
		"blurb": "A piercing blast that ignites what it touches.",
		"cost": 40.0,
		"color": Color(1.0, 0.5, 0.12),
	},
	IMPACT_DASH: {
		"name": "IMPACT DASH",
		"blurb": "An armoured charge that shatters what it hits.",
		"cost": 35.0,
		"color": Color(0.6, 0.78, 1.0),
	},
	RISK_POOL: {
		"name": "RISK POOL",
		"blurb": "Drops a column of liabilities on whatever you aim at.",
		"cost": 45.0,
		"color": Color(0.72, 0.66, 1.0),
	},
	UNDERTOW: {
		"name": "UNDERTOW",
		"blurb": "Drags every peril within reach into Munch range, hurt.",
		"cost": 38.0,
		"color": Color(0.36, 0.78, 0.86),
	},
	CLAUSE_BREAKER: {
		"name": "CLAUSE BREAKER",
		"blurb": "A pound that cracks armour nothing else opens.",
		"cost": 42.0,
		"color": Color(0.95, 0.82, 0.35),
	},
	SALVAGE_HOOK: {
		"name": "SALVAGE HOOK",
		"blurb": "A line to the nearest wall, and your air back.",
		"cost": 30.0,
		"color": Color(0.78, 0.72, 0.58),
	},
	MASS_CLAIM: {
		"name": "MASS CLAIM",
		"blurb": "Weakens every peril in reach at once, ready to Munch.",
		"cost": 50.0,
		"color": Color(0.55, 0.92, 0.6),
	},
	UNDERWRITE: {
		"name": "UNDERWRITE",
		"blurb": "A charged beam that pierces the whole room.",
		"cost": 48.0,
		"color": Color(1.0, 0.42, 0.72),
	},
}

## §14: holding two abilities creates a third behaviour rather than just
## letting you pick. Keys are sorted id pairs.
const COMBOS := {
	"flame_draft|impact_dash": {
		"name": "MELTDOWN CHARGE",
		"blurb": "The dash ignites everything along its path.",
	},
	"flame_draft|risk_pool": {
		"name": "FIRE SALE",
		"blurb": "Dropped liabilities burst into flame where they land.",
	},
	"flame_draft|undertow": {
		"name": "STEAM CLAIM",
		"blurb": "Everything dragged in arrives already burning.",
	},
	"clause_breaker|flame_draft": {
		"name": "BACKDRAFT",
		"blurb": "The pound erupts instead of landing.",
	},
	"flame_draft|salvage_hook": {
		"name": "FLARE LINE",
		"blurb": "The line burns everything it is strung through.",
	},
	"flame_draft|mass_claim": {
		"name": "MASS COMBUSTION",
		"blurb": "Weakened perils catch, and spread it.",
	},
	"flame_draft|underwrite": {
		"name": "PILOT LIGHT",
		"blurb": "The beam lights what it pierces.",
	},
	"impact_dash|risk_pool": {
		"name": "PILE-UP",
		"blurb": "The charge shatters liabilities into a second wave.",
	},
	"impact_dash|undertow": {
		"name": "RIPTIDE CHARGE",
		"blurb": "The charge drags in everything it passes.",
	},
	"clause_breaker|impact_dash": {
		"name": "DEMOLITION CLAUSE",
		"blurb": "The charge ends in a pound, at speed.",
	},
	"impact_dash|salvage_hook": {
		"name": "TOW LINE",
		"blurb": "The charge can turn off a wall and keep going.",
	},
	"impact_dash|mass_claim": {
		"name": "HIT AND RUN",
		"blurb": "Everything the charge passes is left weakened.",
	},
	"impact_dash|underwrite": {
		"name": "RAM RAID",
		"blurb": "The charge discharges on the first thing it hits.",
	},
	"risk_pool|undertow": {
		"name": "SETTLEMENT SPIRAL",
		"blurb": "Dragged perils are pinned under the falling column.",
	},
	"clause_breaker|risk_pool": {
		"name": "FOUNDATION FAILURE",
		"blurb": "The column lands as a pound, not a drop.",
	},
	"risk_pool|salvage_hook": {
		"name": "CRANE DROP",
		"blurb": "Liabilities fall wherever the line is anchored.",
	},
	"mass_claim|risk_pool": {
		"name": "CLASS ACTION",
		"blurb": "Everything the column touches is left weakened.",
	},
	"risk_pool|underwrite": {
		"name": "ACTUARIAL FIRE",
		"blurb": "The column arrives already charged.",
	},
	"clause_breaker|undertow": {
		"name": "SINKHOLE",
		"blurb": "What the vacuum drags in, the pound flattens.",
	},
	"salvage_hook|undertow": {
		"name": "DRAGNET",
		"blurb": "You and everything near you arrive together.",
	},
	"mass_claim|undertow": {
		"name": "BULK SETTLEMENT",
		"blurb": "Everything dragged in arrives weakened.",
	},
	"undertow|underwrite": {
		"name": "FUNNEL",
		"blurb": "The beam fires straight down the vacuum.",
	},
	"clause_breaker|salvage_hook": {
		"name": "WRECKING BALL",
		"blurb": "The line swings you into the pound.",
	},
	"clause_breaker|mass_claim": {
		"name": "BLUNT FORCE CLAUSE",
		"blurb": "The pound weakens rather than finishes.",
	},
	"clause_breaker|underwrite": {
		"name": "PRESSURE TEST",
		"blurb": "The pound charges the next shot for free.",
	},
	"mass_claim|salvage_hook": {
		"name": "SALVAGE RIGHTS",
		"blurb": "Whatever the line reaches is left weakened.",
	},
	"salvage_hook|underwrite": {
		"name": "ZIP LINE",
		"blurb": "The beam fires along the line, end to end.",
	},
	"mass_claim|underwrite": {
		"name": "BLANKET POLICY",
		"blurb": "The beam weakens everything it passes through.",
	},
}


static func entry(id: String) -> Dictionary:
	return ABILITIES.get(id, ABILITIES[FLAME_DRAFT])


static func cost(id: String) -> float:
	return float(entry(id).get("cost", 40.0))


## The combo formed by what you are holding.
##
## This used to sort every owned id and look the joined string up directly,
## which worked with exactly two abilities and silently stopped the moment you
## beat a second boss: three ids join to "a|b|c", no key matches, and MELTDOWN
## CHARGE quietly went away at the point the player had earned the most. Every
## pair is considered now, and `equipped` breaks the tie so the combo follows
## the ability actually selected.
static func combo_for(owned: Array, equipped: String = "") -> Dictionary:
	if owned.size() < 2:
		return {}
	var ids := PackedStringArray()
	for id in owned:
		ids.append(String(id))
	ids.sort()
	var fallback := {}
	for i in ids.size():
		for j in range(i + 1, ids.size()):
			var found: Dictionary = COMBOS.get("%s|%s" % [ids[i], ids[j]], {})
			if found.is_empty():
				continue
			if equipped != "" and (ids[i] == equipped or ids[j] == equipped):
				return found
			if fallback.is_empty():
				fallback = found
	return fallback
