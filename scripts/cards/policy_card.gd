class_name PolicyCard
extends RefCounted
## One Policy Card (GAME_DESIGN.md §9) or Exclusion (§10).
##
## Cards are pure data: a bag of additive modifiers and multipliers keyed by
## stat name. Nothing in the player controller knows any individual card
## exists — it only asks GameManager for the current value of a stat. That is
## what lets designers add cards without touching core systems (§29, §30).

enum Rarity { COMMON, UNCOMMON, RARE }

var id: String = ""
var title: String = ""
var text: String = ""
var category: String = "Utility"
var rarity: int = Rarity.COMMON
## Additive modifiers, e.g. {"max_coverage": 25}
var mods: Dictionary = {}
## Multiplicative modifiers, e.g. {"damage_mult": 1.25}
var mults: Dictionary = {}
## Exclusions are visually distinct and always disclose the downside (§10).
var is_exclusion: bool = false
var downside: String = ""
## How many copies may be held. Most cards stack; a few are once-only.
var max_stacks: int = 3


static func make(data: Dictionary) -> PolicyCard:
	var card := PolicyCard.new()
	card.id = String(data.get("id", ""))
	card.title = String(data.get("title", "Untitled Policy"))
	card.text = String(data.get("text", ""))
	card.category = String(data.get("category", "Utility"))
	card.rarity = int(data.get("rarity", Rarity.COMMON))
	card.mods = data.get("mods", {})
	card.mults = data.get("mults", {})
	card.is_exclusion = bool(data.get("is_exclusion", false))
	card.downside = String(data.get("downside", ""))
	card.max_stacks = int(data.get("max_stacks", 3))
	return card


func rarity_name() -> String:
	match rarity:
		Rarity.RARE:
			return "RARE"
		Rarity.UNCOMMON:
			return "UNCOMMON"
		_:
			return "STANDARD"


func rarity_color() -> Color:
	match rarity:
		Rarity.RARE:
			return Color(1.0, 0.78, 0.25)
		Rarity.UNCOMMON:
			return Color(0.55, 0.85, 1.0)
		_:
			return Color(0.82, 0.86, 0.94)
