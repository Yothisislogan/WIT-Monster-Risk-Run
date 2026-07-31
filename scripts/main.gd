extends Node2D
## Main gameplay scene: hosts the player, swaps room modules in and out,
## and reacts to run lifecycle events. Resumes a saved run on launch
## (GAME_DESIGN.md §5, §17, §24).

const FALL_LIMIT_Y := 900.0
## Falling in a pit costs Coverage and drops you back on solid ground.
## It never ends a run outright — that felt like a bug, not a challenge.
const PIT_DAMAGE := 12

@onready var room_container: Node2D = $RoomContainer
@onready var player: Player = $Player
@onready var hud := $HUD

var current_room: Room
var _safe_position: Vector2 = Vector2.ZERO
var _safe_timer: float = 0.0


func _ready() -> void:
	hud.restart_requested.connect(_on_restart_requested)
	Events.run_ended.connect(_on_run_ended)
	if not GameManager.resume_run():
		GameManager.start_new_run()
	_load_room(GameManager.current_room_path())


func _physics_process(delta: float) -> void:
	if not GameManager.run_active:
		return
	_track_safe_ground(delta)
	if player.global_position.y > FALL_LIMIT_Y:
		_recover_from_pit()


## Remember the last place the player stood still enough to respawn onto.
func _track_safe_ground(delta: float) -> void:
	_safe_timer -= delta
	if _safe_timer > 0.0 or not player.is_on_floor():
		return
	_safe_timer = 0.25
	_safe_position = player.global_position


func _recover_from_pit() -> void:
	player.velocity = Vector2.ZERO
	var target := _safe_position
	if target == Vector2.ZERO:
		target = current_room.spawn_point.global_position
	player.global_position = target - Vector2(0.0, 24.0)
	Juice.shake(6.0, 0.3)
	GameManager.damage(PIT_DAMAGE, "swallowed by an uninsured sinkhole")


func _load_room(path: String) -> void:
	if is_instance_valid(current_room):
		current_room.queue_free()
	current_room = load(path).instantiate()
	room_container.add_child(current_room)
	current_room.exit_reached.connect(_on_room_exit_reached)
	player.global_position = current_room.spawn_point.global_position
	player.velocity = Vector2.ZERO
	player.set_physics_process(true)
	_safe_position = current_room.spawn_point.global_position
	_safe_timer = 0.0
	Events.room_started.emit(path)


func _on_room_exit_reached() -> void:
	GameManager.complete_room()
	if GameManager.run_active:
		_load_room(GameManager.current_room_path())


func _on_run_ended(_report: Dictionary) -> void:
	# Freeze gameplay under the claim report overlay.
	player.set_physics_process(false)


func _on_restart_requested() -> void:
	GameManager.start_new_run()
	_load_room(GameManager.current_room_path())
