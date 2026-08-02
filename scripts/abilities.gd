class_name Abilities
extends RefCounted
## Boss abilities absorbed from defeated bosses (GAME_DESIGN.md §12) and the
## combinations they form when you hold more than one (§14).
##
## Data only: the player controller asks which ability is equipped and what
## its combo is, and never hard-codes a list.

const FLAME_DRAFT := "flame_draft"
const IMPACT_DASH := "impact_dash"

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
}

## §14: holding two abilities creates a third behaviour rather than just
## letting you pick. Keys are sorted id pairs.
const COMBOS := {
	"flame_draft|impact_dash": {
		"name": "MELTDOWN CHARGE",
		"blurb": "The dash ignites everything along its path.",
	},
}


static func entry(id: String) -> Dictionary:
	return ABILITIES.get(id, ABILITIES[FLAME_DRAFT])


static func cost(id: String) -> float:
	return float(entry(id).get("cost", 40.0))


static func combo_for(owned: Array) -> Dictionary:
	if owned.size() < 2:
		return {}
	var sorted_ids := PackedStringArray()
	for id in owned:
		sorted_ids.append(String(id))
	sorted_ids.sort()
	return COMBOS.get("|".join(sorted_ids), {})
