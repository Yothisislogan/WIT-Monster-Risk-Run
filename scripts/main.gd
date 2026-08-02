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
## True while the card picker is up and the next room is waiting on a choice.
var _awaiting_card: bool = false


func _ready() -> void:
	hud.restart_requested.connect(_on_restart_requested)
	Events.run_ended.connect(_on_run_ended)
	Events.card_chosen.connect(_on_card_chosen)
	Events.node_chosen.connect(_enter_node)
	Events.site_resolved.connect(_on_site_resolved)
	Settings.apply_all()
	# Normally the title screen has already started or resumed the run; this
	# keeps main.tscn runnable on its own for quick iteration.
	if not GameManager.run_active and not GameManager.resume_run():
		GameManager.start_new_run()
	_resume_route()


## Pick up wherever the route is: mid-site after a reload, or at a fork.
func _resume_route() -> void:
	if GameManager.map.current_id >= 0 and GameManager.available_nodes().is_empty():
		_open_current_site()
		return
	_open_map()


func _open_map() -> void:
	Events.map_opened.emit(GameManager.available_nodes())


## A site is either a room you play or a screen you answer. Combat loads the
## room; everything else is presented by the HUD, which answers on
## Events.site_resolved.
func _enter_node(id: int) -> void:
	if not GameManager.enter_node(id):
		return
	_open_current_site()


func _open_current_site() -> void:
	var kind := GameManager.current_kind()
	if ClaimMap.is_combat(kind):
		_load_room(GameManager.current_room_path())
		return
	Events.site_opened.emit(GameManager.map.current_id, kind)


func _on_site_resolved() -> void:
	_finish_site()


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
	player.reset_for_room()
	player.apply_camera_bounds(current_room.camera_bounds)
	_safe_position = current_room.spawn_point.global_position
	_safe_timer = 0.0
	GameManager.begin_room()
	Events.room_started.emit(path)


func _on_room_exit_reached() -> void:
	_finish_site()


func _finish_site() -> void:
	var was_combat := ClaimMap.is_combat(GameManager.current_kind())
	GameManager.complete_room()
	if not GameManager.run_active:
		return
	# An endorsement is the reward for a fight (§9), so the sites you route
	# through to avoid fighting do not also hand you cards. The HUD pauses
	# while the choice is open and answers on Events.card_chosen.
	var offers := GameManager.draw_card_offers(3) if was_combat else []
	if offers.is_empty():
		_open_map()
		return
	_awaiting_card = true
	Events.cards_offered.emit(offers)


func _on_card_chosen(card_id: String) -> void:
	if not _awaiting_card:
		return
	_awaiting_card = false
	if card_id != "":
		GameManager.add_card(card_id)
	if GameManager.run_active:
		_open_map()


func _on_run_ended(report: Dictionary) -> void:
	# A win freezes the frame under the claim report. A loss does not: the
	# Monster's death fall is the last thing you watch, and player.gd drives
	# it from its own _dead state until the HUD fades the screen out.
	if bool(report.get("victory", false)):
		player.set_physics_process(false)


func _on_restart_requested() -> void:
	_awaiting_card = false
	GameManager.start_new_run(GameManager.deductible)
	_open_map()
