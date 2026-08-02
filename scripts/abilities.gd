class_name Abilities
extends RefCounted
## Boss abilities absorbed from defeated bosses (GAME_DESIGN.md §12) and the
## combinations they form when you hold more than one (§14).
##
## Data only: the player controller asks which ability is equipped and what
## its combo is, and never hard-codes a list.

const FLAME_DRAFT := "flame_draft"
const IMPACT_DASH := "impact_dash"
const RISK_POOL := "risk_pool"
const UNDERTOW := "undertow"

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
}

## §14: holding two abilities creates a third behaviour rather than just
## letting you pick. Keys are sorted id pairs. Every pair has an entry —
## tools/check_bosses.py fails if one is missing, because a missing pair is
## invisible in play: the player simply never sees a combo and cannot tell
## whether that is the design or a gap.
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
	"impact_dash|risk_pool": {
		"name": "TOTAL LOSS",
		"blurb": "The charge shatters liabilities into a second wave.",
	},
	"impact_dash|undertow": {
		"name": "RIPTIDE CHARGE",
		"blurb": "The charge drags in everything it passes.",
	},
	"risk_pool|undertow": {
		"name": "SETTLEMENT SPIRAL",
		"blurb": "Dragged perils are pinned under the falling column.",
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
