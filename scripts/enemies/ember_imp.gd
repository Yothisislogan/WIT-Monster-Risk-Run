extends EnemyBase
## Ember Imp (§16 flying role). Drifts on a sine path, then telegraphs and
## dives at the Monster. Readable on a phone: it flashes and holds still
## before committing, so the dive is always the player's fault.

@export var drift_speed: float = 70.0
@export var bob_amplitude: float = 34.0
@export var bob_speed: float = 2.2
@export var detect_range: float = 300.0
@export var telegraph_time: float = 0.5
@export var dive_speed: float = 460.0
@export var recover_time: float = 1.1

enum State { DRIFT, TELEGRAPH, DIVE, RECOVER }

@onready var visual: Node2D = $Visual

var _state: int = State.DRIFT
var _timer: float = 0.0
var _age: float = 0.0
var _origin: Vector2 = Vector2.ZERO
var _direction: int = -1
var _dive_vector: Vector2 = Vector2.ZERO
var _player: Player = null


func _ready() -> void:
	super._ready()
	_origin = global_position
	var players := get_tree().get_nodes_in_group("player")
	if not players.is_empty():
		_player = players[0]


func _physics_process(delta: float) -> void:
	_age += delta
	match _state:
		State.DRIFT:
			_drift(delta)
		State.TELEGRAPH:
			_telegraph(delta)
		State.DIVE:
			_dive(delta)
		State.RECOVER:
			_recover(delta)
	visual.scale.x = absf(visual.scale.x) * -_direction
	move_and_slide()


func _drift(delta: float) -> void:
	velocity.x = _direction * drift_speed
	velocity.y = cos(_age * bob_speed) * bob_amplitude
	if is_on_wall():
		_direction *= -1
	if is_instance_valid(_player) and global_position.distance_to(_player.global_position) < detect_range:
		_enter(State.TELEGRAPH, telegraph_time)


func _telegraph(delta: float) -> void:
	# Hover and pulse — the tell that a dive is coming.
	velocity = velocity.lerp(Vector2.ZERO, 1.0 - exp(-10.0 * delta))
	var pulse := 1.0 + sin(_age * 34.0) * 0.16
	visual.scale = Vector2(absf(visual.scale.x) * -_direction, pulse)
	visual.modulate = Color(1.6, 1.0, 0.8)
	_timer -= delta
	if _timer <= 0.0:
		visual.modulate = Color.WHITE
		var target := _player.global_position if is_instance_valid(_player) else global_position + Vector2.DOWN * 100.0
		_dive_vector = (target - global_position).normalized()
		_direction = 1 if _dive_vector.x > 0.0 else -1
		_enter(State.DIVE, 1.0)


func _dive(delta: float) -> void:
	velocity = _dive_vector * dive_speed
	_timer -= delta
	if _timer <= 0.0 or is_on_floor() or is_on_wall():
		if is_on_floor():
			Juice.dust(global_position, 6)
		_enter(State.RECOVER, recover_time)


func _recover(delta: float) -> void:
	# Climb back to the patrol altitude before it can threaten again.
	velocity = velocity.lerp(Vector2(_direction * drift_speed, -110.0), 1.0 - exp(-4.0 * delta))
	_timer -= delta
	if _timer <= 0.0:
		_origin.y = global_position.y
		_enter(State.DRIFT, 0.0)


func _enter(state: int, timer: float) -> void:
	_state = state
	_timer = timer


func _on_damaged() -> void:
	super._on_damaged()
	# Getting shot mid-telegraph cancels the dive — rewards reacting to the tell.
	if _state == State.TELEGRAPH:
		visual.modulate = Color.WHITE
		_enter(State.RECOVER, recover_time * 0.5)
