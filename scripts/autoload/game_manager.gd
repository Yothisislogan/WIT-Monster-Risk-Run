extends Node
## Owns run state (Coverage, currency, upgrades, room progress) and saves a
## checkpoint after every completed room so mobile players can close the app
## and resume (GAME_DESIGN.md §5, §17, §24).

## Handcrafted room modules for the prototype. The roguelite framework
## (Phase 3) will replace this with randomized sequencing per Risk Zone.
const ROOM_SEQUENCE: Array[String] = [
	"res://scenes/rooms/test_room_a.tscn",
	"res://scenes/rooms/test_room_b.tscn",
]

const BASE_COVERAGE := 100

var max_coverage: int = BASE_COVERAGE
var coverage: int = BASE_COVERAGE
var currency: int = 0
var umbrella_active: bool = false  # Umbrella Coverage: blocks one hit
var room_index: int = 0
var run_active: bool = false
var last_damage_source: String = "unknown peril"

var stats := {
	"rooms_completed": 0,
	"damage_taken": 0,
	"enemies_defeated": 0,
}


func _ready() -> void:
	# Keep receiving focus notifications while the tree is paused.
	process_mode = Node.PROCESS_MODE_ALWAYS


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
	room_index = 0
	run_active = true
	last_damage_source = "unknown peril"
	stats = {"rooms_completed": 0, "damage_taken": 0, "enemies_defeated": 0}
	SaveManager.clear_run()
	Events.run_started.emit()
	Events.coverage_changed.emit(coverage, max_coverage)
	Events.currency_changed.emit(currency)


func resume_run() -> bool:
	var run: Dictionary = SaveManager.get_section("run")
	if run.is_empty():
		return false
	max_coverage = int(run.get("max_coverage", BASE_COVERAGE))
	coverage = int(run.get("coverage", max_coverage))
	currency = int(run.get("currency", 0))
	umbrella_active = bool(run.get("umbrella_active", false))
	room_index = clampi(int(run.get("room_index", 0)), 0, ROOM_SEQUENCE.size() - 1)
	stats = run.get("stats", stats)
	run_active = true
	Events.run_started.emit()
	Events.coverage_changed.emit(coverage, max_coverage)
	Events.currency_changed.emit(currency)
	return true


func current_room_path() -> String:
	return ROOM_SEQUENCE[room_index]


## Called when the exit door of a room is reached. Saves a checkpoint at the
## start of the next room; the room itself is never re-rolled on resume (§17).
func complete_room() -> void:
	stats["rooms_completed"] = int(stats["rooms_completed"]) + 1
	Events.room_completed.emit(current_room_path())
	if room_index + 1 >= ROOM_SEQUENCE.size():
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
	coverage = maxi(coverage - amount, 0)
	stats["damage_taken"] = int(stats["damage_taken"]) + amount
	Events.player_damaged.emit(amount, source)
	Events.coverage_changed.emit(coverage, max_coverage)
	if coverage == 0:
		Events.player_died.emit(source)
		end_run(false)


func heal(amount: int) -> void:
	coverage = mini(coverage + amount, max_coverage)
	Events.coverage_changed.emit(coverage, max_coverage)


func add_currency(amount: int) -> void:
	currency += amount
	Events.currency_changed.emit(currency)


func grant_umbrella() -> void:
	umbrella_active = true
	Events.shield_changed.emit(true)
	Events.upgrade_gained.emit("umbrella_coverage")


func record_enemy_defeated() -> void:
	stats["enemies_defeated"] = int(stats["enemies_defeated"]) + 1


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
		"estimated_property_damage": property_damage,
		"claim_status": "Approved. Somehow." if victory else "Under review.",
		"victory": victory,
	}
