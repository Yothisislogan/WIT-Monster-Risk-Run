class_name CaseFiles
extends RefCounted
## Case Files — the achievement set (GAME_DESIGN.md §24).
##
## Each one is a play pattern the game would like you to try, written as a
## claim your employer has filed about you. They pay Case Files, which is the
## Headquarters currency, so an achievement is never only a sticker.
##
## Conditions are data — a field of the claim report, a floor, a ceiling — so
## the whole table is checkable by tools/check_meta.py without running the
## game. Anything needing bespoke logic does not belong here.

const FILES := [
	{"id": "first_notice", "title": "FIRST NOTICE OF LOSS",
	 "blurb": "File your first claim, by any means, in any condition.",
	 "stat": "rooms_completed", "min": 1},

	{"id": "total_loss", "title": "TOTAL LOSS",
	 "blurb": "Cause eight figures of property damage in a single run.",
	 "stat": "estimated_property_damage", "min": 10_000_000},

	{"id": "no_claims_bonus", "title": "NO-CLAIMS BONUS",
	 "blurb": "Survey six sites in one run without losing any Coverage.",
	 "stat": "damage_taken", "max": 0, "and_stat": "rooms_completed", "and_min": 6},

	{"id": "preferred_risk", "title": "PREFERRED RISK",
	 "blurb": "Finish a run with your Risk assessment under 20%.",
	 "stat": "risk", "max": 0.2, "and_stat": "rooms_completed", "and_min": 6},

	{"id": "uninsurable", "title": "UNINSURABLE",
	 "blurb": "Finish a run at the top of the Risk Meter. Nobody will cover you now.",
	 "stat": "risk", "min": 0.95},

	{"id": "aggressive_adjusting", "title": "AGGRESSIVE ADJUSTING",
	 "blurb": "Reach a streak of fifteen without being interrupted.",
	 "stat": "best_combo", "min": 15},

	{"id": "balanced_diet", "title": "BALANCED DIET",
	 "blurb": "Consume twenty parties in one run. Nutritionally, a concern.",
	 "stat": "enemies_consumed", "min": 20},

	{"id": "well_documented", "title": "WELL DOCUMENTED",
	 "blurb": "Hold eight endorsements at once. The policy is now a book.",
	 "stat": "cards", "min": 8},

	{"id": "senior_partner", "title": "SENIOR PARTNER",
	 "blurb": "Defeat three Catastrophes in a single run.",
	 "stat": "bosses_defeated", "min": 3},

	{"id": "settled", "title": "SETTLED IN FULL",
	 "blurb": "Win a run. Somebody, somewhere, has been paid.",
	 "stat": "rooms_completed", "min": 1, "requires_victory": true},

	{"id": "high_deductible", "title": "ASSUMED THE RISK",
	 "blurb": "Win a run on a High Deductible policy.",
	 "stat": "rooms_completed", "min": 1, "requires_victory": true,
	 "deductible": "high"},

	{"id": "meltdown", "title": "MELTDOWN CHARGE",
	 "blurb": "Hold two absorbed powers at the same time.",
	 "stat": "abilities_held", "min": 2},
]


static func _profile() -> Dictionary:
	return SaveManager.get_section("profile")


static func earned() -> Array:
	return (_profile().get("case_files_earned", []) as Array)


static func has(id: String) -> bool:
	return id in earned()


static func entry(id: String) -> Dictionary:
	for file in FILES:
		if String(file["id"]) == id:
			return file
	return {}


static func _satisfied(file: Dictionary, report: Dictionary) -> bool:
	if bool(file.get("requires_victory", false)) and not bool(report.get("victory", false)):
		return false
	if file.has("deductible") \
			and String(report.get("deductible_id", "")) != String(file["deductible"]):
		return false
	var value := float(report.get(String(file["stat"]), 0))
	if file.has("min") and value < float(file["min"]):
		return false
	if file.has("max") and value > float(file["max"]):
		return false
	if file.has("and_stat"):
		var other := float(report.get(String(file["and_stat"]), 0))
		if file.has("and_min") and other < float(file["and_min"]):
			return false
	return true


## Evaluates the whole table against a finished run and records anything newly
## earned. Returns the new ones, so the claim report can show them.
static func evaluate(report: Dictionary) -> Array:
	var already := earned()
	var fresh: Array = []
	for file in FILES:
		var id := String(file["id"])
		if id in already or not _satisfied(file, report):
			continue
		already.append(id)
		fresh.append(file)
	if fresh.is_empty():
		return []
	var profile := _profile()
	profile["case_files_earned"] = already
	SaveManager.set_section("profile", profile)
	return fresh
