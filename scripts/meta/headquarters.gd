class_name Headquarters
extends RefCounted
## WIT HEADQUARTERS — permanent progression between runs (GAME_DESIGN.md §24).
##
## The problem this solves: the only thing that survived a run was a win
## counter. Premiums evaporated at the claim report, so run two started
## exactly where run one did. That is a roguelite with no reason to play it
## twice.
##
## The currency is CASE FILES. Every run files them whether you win or lose —
## losing files more interesting ones — so a bad run is still worth something,
## which is the whole job of a meta-currency.
##
## The anti-power-creep answer, because §24 is right to worry about it: most
## of what you buy here unlocks OPTIONS rather than power. Two thirds of the
## catalogue below opens cards, sites and abilities into the pool; the handful
## that are straight numbers are small, capped at three ranks, and deliberately
## front-loaded so they smooth out runs one to five and then stop mattering.
## tools/check_meta.py asserts that ceiling rather than trusting this comment.

## Case Files awarded for a run, before the win bonus. Tuned in check_meta.py
## against how many runs it takes to buy the catalogue.
const FILES_PER_SITE := 3
const FILES_PER_BOSS := 12
const FILES_FOR_WIN := 25
const FILES_PER_NEW_CASE_FILE := 8

const UPGRADES := [
	{
		"id": "standard_issue",
		"title": "STANDARD ISSUE COVERAGE",
		"blurb": "Legal have approved a slightly larger policy for field staff.",
		"effect": "+8 starting Coverage per rank.",
		"ranks": 3, "costs": [30, 55, 90],
		"stat": "max_coverage", "per_rank": 8.0,
	},
	{
		"id": "signing_bonus",
		"title": "SIGNING BONUS",
		"blurb": "Paid on commencement. Non-refundable, as you keep proving.",
		"effect": "Start each run with 30 Premiums per rank.",
		"ranks": 3, "costs": [25, 45, 75],
		"currency": 30,
	},
	{
		"id": "field_training",
		"title": "FIELD TRAINING",
		"blurb": "A morning course. Mostly slides. Something stuck.",
		"effect": "Start each run with 25 ability energy per rank.",
		"ranks": 2, "costs": [40, 80],
		"energy": 25.0,
	},
	{
		"id": "corporate_umbrella",
		"title": "CORPORATE UMBRELLA",
		"blurb": "Issued to everyone. Nobody has read the terms.",
		"effect": "Begin every run with Umbrella Coverage attached.",
		"ranks": 1, "costs": [70],
		"umbrella": true,
	},
	{
		"id": "clean_record",
		"title": "CLEAN RECORD",
		"blurb": "Your file has been, at considerable expense, tidied.",
		"effect": "Start each run at lower assessed Risk.",
		"ranks": 2, "costs": [45, 85],
		"risk": -0.05,
	},
	# --- Unlocks: these open the catalogue rather than raising a number -----
	{
		"id": "portfolio_a",
		"title": "EXPANDED PORTFOLIO I",
		"blurb": "Underwriting will now consider the interesting endorsements.",
		"effect": "Adds 3 Policy Cards to the offer pool.",
		"ranks": 1, "costs": [50],
		"unlocks_cards": ["expedited_review", "loss_adjustment", "umbrella_policy"],
	},
	{
		"id": "portfolio_b",
		"title": "EXPANDED PORTFOLIO II",
		"blurb": "And the ones the auditors flagged.",
		"effect": "Adds 3 more Policy Cards, including a rare.",
		"ranks": 1, "costs": [95],
		"unlocks_cards": ["total_loss", "rocket_boots", "roadside_assist"],
	},
	{
		"id": "catastrophe_desk",
		"title": "CATASTROPHE DESK",
		"blurb": "The department nobody visits twice.",
		"effect": "Adds the Exclusions to the offer pool. They pay for themselves.",
		"ranks": 1, "costs": [60],
		"unlocks_exclusions": true,
	},
]

## Cards held back from a new player's pool. Everything locked is situational
## or spiky — the whole common tier stays available from run one, so the first
## run is a smaller catalogue rather than a worse one.
const LOCKED_BY_DEFAULT := [
	"expedited_review", "loss_adjustment", "umbrella_policy",
	"total_loss", "rocket_boots", "roadside_assist",
]


# --- Persistence ------------------------------------------------------------

static func _profile() -> Dictionary:
	return SaveManager.get_section("profile")


static func case_files() -> int:
	return int(_profile().get("case_files", 0))


static func add_case_files(amount: int) -> void:
	if amount <= 0:
		return
	var profile := _profile()
	profile["case_files"] = int(profile.get("case_files", 0)) + amount
	profile["case_files_lifetime"] = int(profile.get("case_files_lifetime", 0)) + amount
	SaveManager.set_section("profile", profile)


static func rank(id: String) -> int:
	return int((_profile().get("hq", {}) as Dictionary).get(id, 0))


static func entry(id: String) -> Dictionary:
	for upgrade in UPGRADES:
		if String(upgrade["id"]) == id:
			return upgrade
	return {}


static func max_rank(id: String) -> int:
	return int(entry(id).get("ranks", 0))


## Cost of the next rank, or -1 when it is already maxed.
static func next_cost(id: String) -> int:
	var upgrade := entry(id)
	var current := rank(id)
	if upgrade.is_empty() or current >= int(upgrade["ranks"]):
		return -1
	return int((upgrade["costs"] as Array)[current])


static func can_buy(id: String) -> bool:
	var cost := next_cost(id)
	return cost >= 0 and case_files() >= cost


static func buy(id: String) -> bool:
	if not can_buy(id):
		return false
	var cost := next_cost(id)
	var profile := _profile()
	profile["case_files"] = int(profile.get("case_files", 0)) - cost
	var hq: Dictionary = profile.get("hq", {})
	hq[id] = rank(id) + 1
	profile["hq"] = hq
	SaveManager.set_section("profile", profile)
	return true


# --- What the run actually starts with --------------------------------------

static func bonus(key: String) -> float:
	var total := 0.0
	for upgrade in UPGRADES:
		if not upgrade.has(key):
			continue
		total += float(upgrade[key]) * float(rank(String(upgrade["id"])))
	return total


static func starting_coverage_bonus() -> int:
	return int(bonus("per_rank"))


static func starting_currency() -> int:
	return int(bonus("currency"))


static func starting_energy() -> float:
	return bonus("energy")


static func starting_risk_bonus() -> float:
	return bonus("risk")


static func starts_with_umbrella() -> bool:
	for upgrade in UPGRADES:
		if upgrade.get("umbrella", false) and rank(String(upgrade["id"])) > 0:
			return true
	return false


## Card ids a new profile cannot be offered yet. Anything not listed in
## LOCKED_BY_DEFAULT is available from the first run.
static func locked_cards() -> Array:
	var locked: Array = LOCKED_BY_DEFAULT.duplicate()
	for upgrade in UPGRADES:
		if rank(String(upgrade["id"])) <= 0:
			continue
		for id in upgrade.get("unlocks_cards", []):
			locked.erase(id)
	return locked


## Exclusions are opt-in progression: a new player is never handed a cursed
## card before they know what a card is (§10).
static func exclusions_unlocked() -> bool:
	for upgrade in UPGRADES:
		if upgrade.get("unlocks_exclusions", false) and rank(String(upgrade["id"])) > 0:
			return true
	return false


# --- Award ------------------------------------------------------------------

## Case Files earned by a finished run. Losing still files them, because a
## meta-currency that only pays on a win is a meta-currency you cannot use
## until you no longer need it.
static func award_for(report: Dictionary, new_case_files: int) -> int:
	var total := FILES_PER_SITE * int(report.get("rooms_completed", 0))
	total += FILES_PER_BOSS * int(report.get("bosses_defeated", 0))
	total += FILES_PER_NEW_CASE_FILE * new_case_files
	if bool(report.get("victory", false)):
		total += FILES_FOR_WIN
	return total
