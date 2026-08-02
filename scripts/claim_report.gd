class_name ClaimReport
extends RefCounted
## Turns a finished run into a claim summary (GAME_DESIGN.md §19).
##
## The joke is bureaucratic understatement about absurd carnage, so the lines
## are picked from how the run actually went rather than at random: what
## killed you, how reckless you were, how much you ate.

const CONTRIBUTING_RECKLESS := [
	"Insured described the Risk Meter as \"a suggestion\".",
	"Insured signed four Exclusions without reading any of them.",
	"Insured was observed sprinting toward the hazard, not away from it.",
	"Policyholder declined all offered safety equipment, twice.",
	"Insured elected to ground-pound a structure they did not own.",
]
const CONTRIBUTING_CAREFUL := [
	"No contributing negligence found. Astonishingly.",
	"Insured took reasonable precautions and was unlucky anyway.",
	"Adjuster notes the insured did everything right. Adjuster is unmoved.",
]
const CONTRIBUTING_GLUTTON := [
	"Insured consumed %d claimants. This is not a covered peril.",
	"Dietary review pending: %d hostile parties were eaten on site.",
	"Insured ate %d of the people they were sent to help.",
]
const CONTRIBUTING_UNTOUCHED := [
	"Insured sustained no damage whatsoever, which we find suspicious.",
	"Zero injuries reported. Investigation into fraud has been opened.",
]
const CONTRIBUTING_GENERIC := [
	"Insured ignored several posted warnings.",
	"Contributing factor: enthusiasm.",
	"Cause partially attributed to a door the insured did not need to open.",
	"Weather was clear. Insured was not.",
]

const STATUS_WIN := [
	"APPROVED. Nobody is happy about it.",
	"PAID IN FULL, under protest.",
	"APPROVED. Your premium has been adjusted accordingly.",
]
const STATUS_LOSS := [
	"DENIED. See attached fine print.",
	"UNDER REVIEW. Indefinitely.",
	"DENIED. Peril was foreseeable and, frankly, foreseen.",
	"PENDING. Adjuster has requested a transfer.",
]
const STATUS_HIGH_RISK := [
	"DENIED, and the file has been forwarded to Legal.",
	"DENIED. This policy is now a case study.",
]


static func compose(report: Dictionary, rng: RandomNumberGenerator) -> Dictionary:
	var victory := bool(report.get("victory", false))
	var risk := float(report.get("risk", 0.0))
	var eaten := int(report.get("enemies_consumed", 0))
	var taken := int(report.get("damage_taken", 0))

	var cause: String
	if victory:
		cause = "Policy limits reached. Claimant survived, regrettably."
	else:
		cause = String(report.get("cause_of_loss", "unknown peril")).capitalize()

	var factor: String
	if eaten >= 3:
		factor = _pick(CONTRIBUTING_GLUTTON, rng) % eaten
	elif taken == 0:
		factor = _pick(CONTRIBUTING_UNTOUCHED, rng)
	elif risk >= 0.6:
		factor = _pick(CONTRIBUTING_RECKLESS, rng)
	elif risk <= 0.15:
		factor = _pick(CONTRIBUTING_CAREFUL, rng)
	else:
		factor = _pick(CONTRIBUTING_GENERIC, rng)

	var status: String
	if victory:
		status = _pick(STATUS_WIN, rng)
	elif risk >= 0.7:
		status = _pick(STATUS_HIGH_RISK, rng)
	else:
		status = _pick(STATUS_LOSS, rng)

	return {"cause": cause, "factor": factor, "status": status}


static func _pick(lines: Array, rng: RandomNumberGenerator) -> String:
	return String(lines[rng.randi() % lines.size()])


## Thousands separators for the property damage figure.
static func money(value: int) -> String:
	var text := str(absi(value))
	var out := ""
	var count := 0
	for i in range(text.length() - 1, -1, -1):
		out = text[i] + out
		count += 1
		if count % 3 == 0 and i > 0:
			out = "," + out
	return out


static func risk_label(risk: float) -> String:
	if risk >= 0.75:
		return "UNINSURABLE"
	if risk >= 0.5:
		return "SEVERE"
	if risk >= 0.25:
		return "ELEVATED"
	return "STANDARD"
