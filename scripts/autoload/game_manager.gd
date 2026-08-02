extends Node
## Owns run state (Coverage, currency, upgrades, room progress) and saves a
## checkpoint after every completed room so mobile players can close the app
## and resume (GAME_DESIGN.md §5, §17, §24).

## Pool of handcrafted room modules. Each run shuffles the pool into a
## sequence (§12: randomize order, never individual platforms). The
## sequence is saved with the run so resuming never re-rolls a room (§17).
const ROOM_POOL: Array[String] = [
	"res://scenes/rooms/test_room_a.tscn",
	"res://scenes/rooms/test_room_b.tscn",
	"res://scenes/rooms/test_room_c.tscn",
]

const BASE_COVERAGE := 100
const MAX_ABILITY_ENERGY := 100.0
const ABILITY_COST := 40.0
## Coverage fraction at or below which the HUD and audio warn you.
const LOW_COVERAGE_RATIO := 0.3
## Chaining takedowns builds an "Adjuster's Streak": more Premiums per kill,
## and it drops the moment you take a hit. Reckless play pays (§11).
const COMBO_WINDOW := 3.0
const COMBO_MAX_MULTIPLIER := 5

var max_coverage: int = BASE_COVERAGE
var coverage: int = BASE_COVERAGE
var currency: int = 0
var umbrella_active: bool = false  # Umbrella Coverage: blocks one hit
var ability_energy: float = 0.0  # fuels the equipped boss ability (Flame Draft)
var room_sequence: Array = []
var room_index: int = 0
var run_active: bool = false
var last_damage_source: String = "unknown peril"

var combo: int = 0
var combo_timer: float = 0.0
var best_combo: int = 0

var stats := {
	"rooms_completed": 0,
	"damage_taken": 0,
	"enemies_defeated": 0,
	"enemies_consumed": 0,
}


func _ready() -> void:
	# Keep receiving focus notifications while the tree is paused.
	process_mode = Node.PROCESS_MODE_ALWAYS


func _process(delta: float) -> void:
	if combo <= 0:
		return
	combo_timer = maxf(combo_timer - delta, 0.0)
	Events.combo_changed.emit(combo, combo_timer / COMBO_WINDOW)
	if combo_timer <= 0.0:
		_reset_combo()


func bump_combo() -> void:
	combo += 1
	best_combo = maxi(best_combo, combo)
	combo_timer = COMBO_WINDOW
	Events.combo_changed.emit(combo, 1.0)


func _reset_combo() -> void:
	combo = 0
	combo_timer = 0.0
	Events.combo_changed.emit(0, 0.0)


func combo_multiplier() -> int:
	return clampi(1 + combo / 3, 1, COMBO_MAX_MULTIPLIER)


func _notification(what: int) -> void:
	# Auto-pause when the app loses focus or is backgrounded (§17).
	match what:
		NOTIFICATION_APPLICATION_FOCUS_OUT, NOTIFICATION_APPLICATION_PAUSED:
			if run_active:
				get_tree().paused = true


# --- Run lifecycle ---------------------------------------------------------

func start_new_run() -> void:
	max_coverage = BASE_COVERAGE
	coverage = max_coverage
	currency = 0
	umbrella_active = false
	ability_energy = 0.0
	combo = 0
	combo_timer = 0.0
	best_combo = 0
	room_sequence = ROOM_POOL.duplicate()
	room_sequence.shuffle()
	room_index = 0
	run_active = true
	last_damage_source = "unknown peril"
	stats = {"rooms_completed": 0, "damage_taken": 0, "enemies_defeated": 0, "enemies_consumed": 0}
	SaveManager.clear_run()
	Events.run_started.emit()
	_emit_state()


func resume_run() -> bool:
	var run: Dictionary = SaveManager.get_section("run")
	if run.is_empty():
		return false
	max_coverage = int(run.get("max_coverage", BASE_COVERAGE))
	coverage = int(run.get("coverage", max_coverage))
	currency = int(run.get("currency", 0))
	umbrella_active = bool(run.get("umbrella_active", false))
	ability_energy = clampf(float(run.get("ability_energy", 0.0)), 0.0, MAX_ABILITY_ENERGY)
	best_combo = int(run.get("best_combo", 0))
	_reset_combo()
	# Drop any rooms that no longer exist in the pool (renamed between builds).
	room_sequence = run.get("room_sequence", []).filter(func(p: Variant) -> bool: return p in ROOM_POOL)
	if room_sequence.is_empty():
		room_sequence = ROOM_POOL.duplicate()
		room_sequence.shuffle()
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


func current_room_path() -> String:
	return room_sequence[room_index]


## Called when the exit door of a room is reached. Saves a checkpoint at the
## start of the next room; the room itself is never re-rolled on resume (§17).
func complete_room() -> void:
	stats["rooms_completed"] = int(stats["rooms_completed"]) + 1
	Sfx.play("room_clear")
	Events.room_completed.emit(current_room_path())
	if room_index + 1 >= room_sequence.size():
		end_run(true)
		return
	room_index += 1
	save_checkpoint()


func save_checkpoint() -> void:
	SaveManager.set_section("run", {
		"max_coverage": max_coverage,
		"coverage": coverage,
		"currency": currency,
		"umbrella_active": umbrella_active,
		"ability_energy": ability_energy,
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
	SaveManager.set_section("stats", lifetime)
	Events.run_ended.emit(build_claim_report(victory))


# --- Coverage / damage -----------------------------------------------------

func damage(amount: int, source: String) -> void:
	if not run_active:
		return
	if umbrella_active:
		umbrella_active = false
		Events.shield_changed.emit(false)
		return
	last_damage_source = source
	_reset_combo()  # getting hit ends the streak
	coverage = maxi(coverage - amount, 0)
	stats["damage_taken"] = int(stats["damage_taken"]) + amount
	Events.player_damaged.emit(amount, source)
	Events.coverage_changed.emit(coverage, max_coverage)
	# Audible warning the first time a hit drops you into the danger band.
	if coverage > 0 and float(coverage) / float(max_coverage) <= LOW_COVERAGE_RATIO \
			and float(coverage + amount) / float(max_coverage) > LOW_COVERAGE_RATIO:
		Sfx.play("low_coverage", 0.0)
	if coverage == 0:
		Events.player_died.emit(source)
		end_run(false)


func heal(amount: int) -> void:
	coverage = mini(coverage + amount, max_coverage)
	Events.coverage_changed.emit(coverage, max_coverage)


func add_currency(amount: int) -> void:
	currency += amount * combo_multiplier()
	Events.currency_changed.emit(currency)


func grant_umbrella() -> void:
	umbrella_active = true
	Events.shield_changed.emit(true)
	Events.upgrade_gained.emit("umbrella_coverage")


func record_enemy_defeated() -> void:
	stats["enemies_defeated"] = int(stats["enemies_defeated"]) + 1
	add_ability_energy(10.0)
	bump_combo()


## Monster Munch (§7): consuming a weakened enemy restores a little
## Coverage and charges the boss ability meter.
func record_enemy_consumed() -> void:
	stats["enemies_consumed"] = int(stats["enemies_consumed"]) + 1
	heal(10)
	add_ability_energy(25.0)
	bump_combo()


func add_ability_energy(amount: float) -> void:
	ability_energy = clampf(ability_energy + amount, 0.0, MAX_ABILITY_ENERGY)
	Events.ability_energy_changed.emit(ability_energy, MAX_ABILITY_ENERGY)


func try_spend_ability_energy(cost: float = ABILITY_COST) -> bool:
	if ability_energy < cost:
		return false
	ability_energy -= cost
	Events.ability_energy_changed.emit(ability_energy, MAX_ABILITY_ENERGY)
	return true


# --- Claim report ----------------------------------------------------------

func build_claim_report(victory: bool) -> Dictionary:
	var rooms := int(stats["rooms_completed"])
	var taken := int(stats["damage_taken"])
	var property_damage := 250_000 * rooms + 12_345 * taken + 99_999
	return {
		"cause_of_loss": "Policy limits reached" if victory else "Insured was " + last_damage_source,
		"rooms_completed": rooms,
		"damage_taken": taken,
		"enemies_defeated": int(stats["enemies_defeated"]),
		"enemies_consumed": int(stats["enemies_consumed"]),
		"best_combo": best_combo,
		"estimated_property_damage": property_damage,
		"claim_status": "Approved. Somehow." if victory else "Under review.",
		"victory": victory,
	}
