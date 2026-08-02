extends Node
## Owns run state (Coverage, Premiums, Policy Cards, Risk, room progress) and
## saves a checkpoint after every completed room so mobile players can close
## the app and resume (GAME_DESIGN.md §5, §17, §24).

## Pool of handcrafted room modules. Each run shuffles the pool into a
## sequence (§12: randomize order, never individual platforms). The
## sequence is saved with the run so resuming never re-rolls a room (§17).
const ROOM_POOL: Array[String] = [
	"res://scenes/rooms/test_room_a.tscn",
	"res://scenes/rooms/test_room_b.tscn",
	"res://scenes/rooms/test_room_c.tscn",
	"res://scenes/rooms/test_room_d.tscn",
	"res://scenes/rooms/test_room_e.tscn",
]
## Always the last room of a run, when it exists.
const BOSS_ROOM := "res://scenes/rooms/boss_inferno_adjuster.tscn"

const BASE_COVERAGE := 100
const MAX_ABILITY_ENERGY := 100.0
## Coverage fraction at or below which the HUD and audio warn you.
const LOW_COVERAGE_RATIO := 0.3
## Chaining takedowns builds an "Adjuster's Streak": more Premiums per kill,
## and it drops the moment you take a hit. Reckless play pays (§11).
const COMBO_WINDOW := 3.0
const COMBO_MAX_MULTIPLIER := 5

## Deductible presets (§8): difficulty without the words easy/normal/hard.
const DEDUCTIBLES := {
	"low": {
		"label": "LOW DEDUCTIBLE",
		"blurb": "More Coverage, gentler perils, smaller payouts.",
		"coverage": 130, "damage_taken": 0.8, "premium": 0.8, "risk": 0.0,
		"healing": 1.25,
	},
	"standard": {
		"label": "STANDARD DEDUCTIBLE",
		"blurb": "The policy exactly as written.",
		"coverage": 100, "damage_taken": 1.0, "premium": 1.0, "risk": 0.1,
		"healing": 1.0,
	},
	"high": {
		"label": "HIGH DEDUCTIBLE",
		"blurb": "Thin Coverage, angrier perils, far better cards.",
		"coverage": 70, "damage_taken": 1.25, "premium": 1.6, "risk": 0.35,
		"healing": 0.7,
	},
}

var max_coverage: int = BASE_COVERAGE
var coverage: int = BASE_COVERAGE
var currency: int = 0
var umbrella_active: bool = false  # blocks one hit
var ability_energy: float = 0.0    # fuels the equipped boss ability
## Boss abilities absorbed so far (§12). You always start with Flame Draft;
## beating a boss adds its power to the list and you cycle between them.
var abilities: Array = [Abilities.FLAME_DRAFT]
var ability_index: int = 0
var room_sequence: Array = []
var room_index: int = 0
var run_active: bool = false
var last_damage_source: String = "unknown peril"

var deductible: String = "standard"
## 0..1. Raised by reckless choices; scales both danger and reward (§11).
var risk: float = 0.0
var held_cards: Dictionary = {}    # card id -> stacks
var revives_left: int = 0

var combo: int = 0
var combo_timer: float = 0.0
var best_combo: int = 0

var stats := {
	"rooms_completed": 0,
	"damage_taken": 0,
	"enemies_defeated": 0,
	"enemies_consumed": 0,
	"premiums_earned": 0,
}

var _rng := RandomNumberGenerator.new()
var _mods: Dictionary = {}
var _mults: Dictionary = {}
var _healed_this_room: bool = false


func _ready() -> void:
	# Keep receiving focus notifications while the tree is paused.
	process_mode = Node.PROCESS_MODE_ALWAYS
	_rng.randomize()
	_recompute_modifiers()
	Input.joy_connection_changed.connect(_on_joy_connection_changed)


## A pad that dies mid-room leaves the player with no way to move and, worse,
## whatever direction was last held still applied. Pausing is the same
## courtesy as the focus-out auto-pause below (§17).
func _on_joy_connection_changed(_device: int, connected: bool) -> void:
	if connected or not run_active:
		return
	if Input.get_connected_joypads().is_empty():
		get_tree().paused = true


func _process(delta: float) -> void:
	if combo <= 0:
		return
	combo_timer = maxf(combo_timer - delta, 0.0)
	Events.combo_changed.emit(combo, combo_timer / combo_window())
	if combo_timer <= 0.0:
		_reset_combo()


func _notification(what: int) -> void:
	# Auto-pause when the app loses focus or is backgrounded (§17).
	match what:
		NOTIFICATION_APPLICATION_FOCUS_OUT, NOTIFICATION_APPLICATION_PAUSED:
			if run_active:
				get_tree().paused = true


# --- Modifiers -------------------------------------------------------------

## Additive stat from all held cards, e.g. stat("max_coverage").
func stat(name: String, base: float = 0.0) -> float:
	return base + float(_mods.get(name, 0.0))


## Multiplicative stat from all held cards, defaults to 1.0.
func factor(name: String) -> float:
	return float(_mults.get(name, 1.0))


func _recompute_modifiers() -> void:
	_mods.clear()
	_mults.clear()
	for id in held_cards.keys():
		var card := CardDb.by_id(String(id))
		if card == null:
			continue
		var stacks := int(held_cards[id])
		for key in card.mods.keys():
			_mods[key] = float(_mods.get(key, 0.0)) + float(card.mods[key]) * stacks
		for key in card.mults.keys():
			_mults[key] = float(_mults.get(key, 1.0)) * pow(float(card.mults[key]), stacks)


func add_card(id: String) -> void:
	var card := CardDb.by_id(id)
	if card == null:
		return
	held_cards[id] = int(held_cards.get(id, 0)) + 1
	_recompute_modifiers()
	# Taking an Exclusion is exactly the sort of decision the Risk Meter exists
	# to notice (§10, §11).
	if card.is_exclusion:
		add_risk(0.15)
	var new_max := _computed_max_coverage()
	var delta := new_max - max_coverage
	max_coverage = new_max
	if delta > 0:
		coverage += delta
	coverage = clampi(coverage, 1, max_coverage)
	revives_left = int(stat("revives"))
	Events.coverage_changed.emit(coverage, max_coverage)
	Events.upgrade_gained.emit(id)


func card_list() -> Array:
	var out: Array = []
	for id in held_cards.keys():
		var card := CardDb.by_id(String(id))
		if card != null:
			out.append({"card": card, "stacks": int(held_cards[id])})
	return out


func _computed_max_coverage() -> int:
	var base := int(DEDUCTIBLES[deductible]["coverage"])
	return maxi(base + int(stat("max_coverage")), 20)


func combo_window() -> float:
	return COMBO_WINDOW + stat("combo_window")


# --- Risk ------------------------------------------------------------------

func add_risk(amount: float) -> void:
	set_risk(risk + amount)


func set_risk(value: float) -> void:
	var clamped := clampf(value, 0.0, 1.0)
	if is_equal_approx(clamped, risk):
		return
	risk = clamped
	Events.risk_changed.emit(risk)


## Perils get tougher as Risk climbs — that is what the reward pays for.
func enemy_health_factor() -> float:
	return 1.0 + risk * 0.6


func enemy_speed_factor() -> float:
	return 1.0 + risk * 0.35


func premium_factor() -> float:
	return float(DEDUCTIBLES[deductible]["premium"]) * (1.0 + risk * 0.5) * factor("premium_mult")


func damage_taken_factor() -> float:
	return float(DEDUCTIBLES[deductible]["damage_taken"])


# --- Run lifecycle ---------------------------------------------------------

## Rooms drawn per run. Fewer than the pool, so two runs rarely share a
## sequence — variety without making a run longer (§5 run length).
const ROOMS_PER_RUN := 3


func _build_sequence() -> Array:
	var pool: Array = ROOM_POOL.duplicate()
	pool.shuffle()
	var sequence: Array = pool.slice(0, mini(ROOMS_PER_RUN, pool.size()))
	# The boss closes every run once its room exists.
	if ResourceLoader.exists(BOSS_ROOM):
		sequence.append(BOSS_ROOM)
	return sequence


func start_new_run(chosen_deductible: String = "standard") -> void:
	deductible = chosen_deductible if DEDUCTIBLES.has(chosen_deductible) else "standard"
	held_cards.clear()
	_recompute_modifiers()
	max_coverage = _computed_max_coverage()
	coverage = max_coverage
	currency = 0
	umbrella_active = false
	ability_energy = 0.0
	abilities = unlocked_abilities()
	ability_index = 0
	revives_left = 0
	risk = float(DEDUCTIBLES[deductible]["risk"])
	combo = 0
	combo_timer = 0.0
	best_combo = 0
	room_sequence = _build_sequence()
	room_index = 0
	run_active = true
	last_damage_source = "unknown peril"
	stats = {"rooms_completed": 0, "damage_taken": 0, "enemies_defeated": 0,
			"enemies_consumed": 0, "premiums_earned": 0}
	SaveManager.clear_run()
	Events.run_started.emit()
	_emit_state()


func resume_run() -> bool:
	var run: Dictionary = SaveManager.get_section("run")
	if run.is_empty():
		return false
	deductible = String(run.get("deductible", "standard"))
	if not DEDUCTIBLES.has(deductible):
		deductible = "standard"
	held_cards = run.get("held_cards", {})
	_recompute_modifiers()
	max_coverage = int(run.get("max_coverage", _computed_max_coverage()))
	coverage = int(run.get("coverage", max_coverage))
	currency = int(run.get("currency", 0))
	umbrella_active = bool(run.get("umbrella_active", false))
	ability_energy = clampf(float(run.get("ability_energy", 0.0)), 0.0, MAX_ABILITY_ENERGY)
	# Drop abilities that no longer exist, so an older save still loads (§17).
	abilities = run.get("abilities", unlocked_abilities()).filter(
			func(id: Variant) -> bool: return Abilities.ABILITIES.has(String(id)))
	if abilities.is_empty():
		abilities = unlocked_abilities()
	ability_index = clampi(int(run.get("ability_index", 0)), 0, abilities.size() - 1)
	risk = clampf(float(run.get("risk", 0.0)), 0.0, 1.0)
	revives_left = int(run.get("revives_left", 0))
	best_combo = int(run.get("best_combo", 0))
	_reset_combo()
	# Drop any rooms that no longer exist (renamed between builds).
	var known := ROOM_POOL.duplicate()
	known.append(BOSS_ROOM)
	room_sequence = run.get("room_sequence", []).filter(
			func(p: Variant) -> bool: return p in known and ResourceLoader.exists(String(p)))
	if room_sequence.is_empty():
		room_sequence = _build_sequence()
	room_index = clampi(int(run.get("room_index", 0)), 0, room_sequence.size() - 1)
	stats = run.get("stats", stats)
	run_active = true
	Events.run_started.emit()
	_emit_state()
	return true


func _emit_state() -> void:
	Events.coverage_changed.emit(coverage, max_coverage)
	Events.currency_changed.emit(currency)
	Events.shield_changed.emit(umbrella_active)
	Events.ability_energy_changed.emit(ability_energy, MAX_ABILITY_ENERGY)
	Events.ability_changed.emit(current_ability())
	Events.risk_changed.emit(risk)


func current_room_path() -> String:
	return room_sequence[room_index]


func is_final_room() -> bool:
	return room_index >= room_sequence.size() - 1


## Called when the exit of a room is reached.
func complete_room() -> void:
	stats["rooms_completed"] = int(stats["rooms_completed"]) + 1
	Sfx.play("room_clear")
	# Clearing a room without topping up is a gamble, and the meter notices.
	if not _healed_this_room:
		add_risk(0.06)
	Events.room_completed.emit(current_room_path())
	if room_index + 1 >= room_sequence.size():
		end_run(true)
		return
	room_index += 1
	save_checkpoint()


## Main calls this as each room begins, so per-room card effects apply once.
func begin_room() -> void:
	_healed_this_room = false
	if int(stat("shield_per_room")) > 0 and not umbrella_active:
		umbrella_active = true
		Events.shield_changed.emit(true)
	var entry_cost := int(stat("room_entry_damage"))
	if entry_cost > 0:
		coverage = maxi(coverage - entry_cost, 1)
		Events.coverage_changed.emit(coverage, max_coverage)


func save_checkpoint() -> void:
	SaveManager.set_section("run", {
		"deductible": deductible,
		"max_coverage": max_coverage,
		"coverage": coverage,
		"currency": currency,
		"umbrella_active": umbrella_active,
		"ability_energy": ability_energy,
		"abilities": abilities,
		"ability_index": ability_index,
		"risk": risk,
		"held_cards": held_cards,
		"revives_left": revives_left,
		"best_combo": best_combo,
		"room_sequence": room_sequence,
		"room_index": room_index,
		"stats": stats,
	})


func end_run(victory: bool) -> void:
	run_active = false
	SaveManager.clear_run()
	var lifetime: Dictionary = SaveManager.get_section("stats")
	lifetime["runs"] = int(lifetime.get("runs", 0)) + 1
	lifetime["wins"] = int(lifetime.get("wins", 0)) + (1 if victory else 0)
	lifetime["best_property_damage"] = maxi(
			int(lifetime.get("best_property_damage", 0)), _property_damage())
	SaveManager.set_section("stats", lifetime)
	Events.run_ended.emit(build_claim_report(victory))


# --- Coverage / damage -----------------------------------------------------

func damage(amount: int, source: String) -> void:
	if not run_active:
		return
	if umbrella_active:
		umbrella_active = false
		Events.shield_changed.emit(false)
		Sfx.play("ui_confirm", 0.05, 0.7)
		return
	var scaled := maxi(int(round(float(amount) * damage_taken_factor())), 1)
	last_damage_source = source
	_reset_combo()  # getting hit ends the streak
	coverage = maxi(coverage - scaled, 0)
	stats["damage_taken"] = int(stats["damage_taken"]) + scaled
	Events.player_damaged.emit(scaled, source)
	Events.coverage_changed.emit(coverage, max_coverage)
	# Audible warning the first time a hit drops you into the danger band.
	if coverage > 0 and float(coverage) / float(max_coverage) <= LOW_COVERAGE_RATIO \
			and float(coverage + scaled) / float(max_coverage) > LOW_COVERAGE_RATIO:
		Sfx.play("low_coverage", 0.0)
	if coverage == 0:
		if revives_left > 0:
			_revive()
			return
		Events.player_died.emit(source)
		end_run(false)


func _revive() -> void:
	revives_left -= 1
	coverage = maxi(max_coverage / 2, 1)
	umbrella_active = true
	Sfx.play("room_clear")
	Juice.shake(8.0, 0.5)
	Events.shield_changed.emit(true)
	Events.coverage_changed.emit(coverage, max_coverage)


## §8 gives each deductible a different healing rate: Low heals more, High
## heals less. Every heal in the game routes through here.
func healing_factor() -> float:
	return float(DEDUCTIBLES[deductible].get("healing", 1.0))


func heal(amount: int) -> void:
	if amount <= 0:
		return
	_healed_this_room = true
	var scaled := maxi(int(round(float(amount) * healing_factor())), 1)
	coverage = mini(coverage + scaled, max_coverage)
	Events.coverage_changed.emit(coverage, max_coverage)


func add_currency(amount: int) -> void:
	var gained := maxi(int(round(float(amount) * combo_multiplier() * premium_factor())), 1)
	currency += gained
	stats["premiums_earned"] = int(stats["premiums_earned"]) + gained
	Events.currency_changed.emit(currency)


func spend_currency(amount: int) -> bool:
	if currency < amount:
		return false
	currency -= amount
	Events.currency_changed.emit(currency)
	return true


func grant_umbrella() -> void:
	umbrella_active = true
	Events.shield_changed.emit(true)
	Events.upgrade_gained.emit("umbrella_coverage")


func record_enemy_defeated() -> void:
	stats["enemies_defeated"] = int(stats["enemies_defeated"]) + 1
	add_ability_energy(10.0)
	bump_combo()


## Monster Munch (§7): consuming a weakened enemy restores Coverage and
## charges the boss ability meter.
func record_enemy_consumed() -> void:
	stats["enemies_consumed"] = int(stats["enemies_consumed"]) + 1
	heal(10 + int(stat("munch_heal")))
	add_ability_energy(25.0)
	bump_combo()


func add_ability_energy(amount: float) -> void:
	ability_energy = clampf(ability_energy + amount, 0.0, MAX_ABILITY_ENERGY)
	Events.ability_energy_changed.emit(ability_energy, MAX_ABILITY_ENERGY)


func ability_cost() -> float:
	return Abilities.cost(current_ability()) * factor("ability_cost_mult")


func try_spend_ability_energy() -> bool:
	var cost := ability_cost()
	if ability_energy < cost:
		return false
	ability_energy -= cost
	Events.ability_energy_changed.emit(ability_energy, MAX_ABILITY_ENERGY)
	return true


# --- Boss abilities (§12, §14) ---------------------------------------------

func current_ability() -> String:
	if abilities.is_empty():
		return Abilities.FLAME_DRAFT
	return String(abilities[ability_index % abilities.size()])


## Absorbed abilities are permanent (§24, WIT Headquarters). The boss is the
## last thing in a run, so an ability you only keep until the claim report
## would be no reward at all — every later run starts with it instead.
func unlocked_abilities() -> Array:
	var profile: Dictionary = SaveManager.get_section("profile")
	var out: Array = [Abilities.FLAME_DRAFT]
	for id in profile.get("abilities", []):
		var ability_id := String(id)
		if Abilities.ABILITIES.has(ability_id) and not (ability_id in out):
			out.append(ability_id)
	return out


## Beating a boss absorbs its power. Absorbing a second one also unlocks the
## combination the two form together (§14).
func grant_ability(id: String) -> void:
	if not Abilities.ABILITIES.has(id) or id in abilities:
		return
	abilities.append(id)
	ability_index = abilities.size() - 1
	var profile: Dictionary = SaveManager.get_section("profile")
	profile["abilities"] = abilities.duplicate()
	SaveManager.set_section("profile", profile)
	Events.ability_granted.emit(id)
	Events.ability_changed.emit(id)


func cycle_ability() -> void:
	if abilities.size() < 2:
		return
	ability_index = (ability_index + 1) % abilities.size()
	Events.ability_changed.emit(current_ability())
	Events.ability_energy_changed.emit(ability_energy, MAX_ABILITY_ENERGY)


## Non-empty once you hold every ability of a known combination, which changes
## how the equipped ability behaves rather than adding a fourth button.
func active_combo() -> Dictionary:
	return Abilities.combo_for(abilities)


# --- Combo -----------------------------------------------------------------

func bump_combo() -> void:
	combo += 1
	best_combo = maxi(best_combo, combo)
	combo_timer = combo_window()
	Events.combo_changed.emit(combo, 1.0)


func _reset_combo() -> void:
	combo = 0
	combo_timer = 0.0
	Events.combo_changed.emit(0, 0.0)


func combo_multiplier() -> int:
	return clampi(1 + combo / 3, 1, COMBO_MAX_MULTIPLIER)


# --- Card offers -----------------------------------------------------------

func draw_card_offers(count: int = 3) -> Array:
	return CardDb.draw_offers(count, held_cards, risk, _rng)


# --- Claim report ----------------------------------------------------------

func _property_damage() -> int:
	return 250_000 * int(stats["rooms_completed"]) \
			+ 12_345 * int(stats["damage_taken"]) \
			+ 8_400 * int(stats["enemies_defeated"]) + 99_999


func build_claim_report(victory: bool) -> Dictionary:
	return {
		"victory": victory,
		"cause_of_loss": last_damage_source,
		"deductible": String(DEDUCTIBLES[deductible]["label"]),
		"rooms_completed": int(stats["rooms_completed"]),
		"damage_taken": int(stats["damage_taken"]),
		"enemies_defeated": int(stats["enemies_defeated"]),
		"enemies_consumed": int(stats["enemies_consumed"]),
		"premiums_earned": int(stats["premiums_earned"]),
		"best_combo": best_combo,
		"risk": risk,
		"cards": held_cards.size(),
		"estimated_property_damage": _property_damage(),
	}
