extends Node2D
## Main gameplay scene: hosts the player, swaps room modules in and out,
## and reacts to run lifecycle events. Resumes a saved run on launch
## (GAME_DESIGN.md §5, §17, §24).

const FALL_DEATH_Y := 900.0

@onready var room_container: Node2D = $RoomContainer
@onready var player: Player = $Player
@onready var hud := $HUD

var current_room: Room


func _ready() -> void:
	hud.restart_requested.connect(_on_restart_requested)
	Events.run_ended.connect(_on_run_ended)
	if not GameManager.resume_run():
		GameManager.start_new_run()
	_load_room(GameManager.current_room_path())


func _physics_process(_delta: float) -> void:
	# Safety net: falling out of a room is an uncovered loss.
	if GameManager.run_active and player.global_position.y > FALL_DEATH_Y:
		GameManager.damage(GameManager.coverage, "lost in an uncovered pit")


func _load_room(path: String) -> void:
	if is_instance_valid(current_room):
		current_room.queue_free()
	current_room = load(path).instantiate()
	room_container.add_child(current_room)
	current_room.exit_reached.connect(_on_room_exit_reached)
	player.global_position = current_room.spawn_point.global_position
	player.velocity = Vector2.ZERO
	player.set_physics_process(true)
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
