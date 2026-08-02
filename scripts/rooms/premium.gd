extends Area2D
## "Premium" — the collectible coin. Coins placed in a room hover where the
## designer put them; coins popped out of crates and enemies arc, land on the
## first surface below, and settle. Both magnetise to the Monster so
## collection always feels generous.

@export var value: int = 1
@export var magnet_radius: float = 130.0
@export var magnet_speed: float = 900.0
## Not `gravity`: Area2D declares one natively and redefining it is a
## parse error that stops the scene loading.
@export var fall_gravity: float = 1400.0
@export var max_fall_speed: float = 900.0
## Only dropped coins expire. Hand-placed ones stay until they are collected.
@export var drop_lifetime: float = 25.0

const COIN_RADIUS := 14.0
const COLLECT_DISTANCE := 26.0

@onready var visual: Node2D = $Visual
@onready var ground_probe: RayCast2D = $GroundProbe

var _velocity: Vector2 = Vector2.ZERO
## Only ever true for coins that were popped from a source. A coin placed in
## a room scene must never fall — it has no ground under it by design.
var _falling: bool = false
var _dropped: bool = false
var _age: float = 0.0
var _collect_delay: float = 0.0
var _player: Player = null


func _ready() -> void:
	_resolve_player()


func _resolve_player() -> void:
	var players := get_tree().get_nodes_in_group("player")
	if not players.is_empty():
		_player = players[0]


## Called by crates and enemies before the coin is added to the tree.
## Gives it an arc plus a short delay so a payout reads as a payout.
func pop(impulse: Vector2) -> void:
	_velocity = impulse
	_falling = true
	_dropped = true
	_collect_delay = 0.25


func _physics_process(delta: float) -> void:
	_age += delta
	_collect_delay = maxf(_collect_delay - delta, 0.0)
	if _dropped and _age > drop_lifetime:
		queue_free()
		return
	if global_position.y > 1200.0:
		queue_free()  # dropped into a pit; nothing to land on
		return

	# Idle bob so a resting Premium still catches the eye on a small screen.
	visual.position.y = sin(_age * 5.0) * 3.0
	visual.rotation = sin(_age * 3.0) * 0.35

	if _magnetise(delta):
		return
	if _falling:
		_fall(delta)


## Returns true while the coin is under the magnet's control.
func _magnetise(delta: float) -> bool:
	if _collect_delay > 0.0:
		return false
	if not is_instance_valid(_player):
		_resolve_player()
		if not is_instance_valid(_player):
			return false
	var to_player := _player.global_position - global_position
	var distance := to_player.length()
	if distance >= magnet_radius * GameManager.factor("coin_magnet_mult") or distance <= 0.0:
		return false
	# The magnet overrides gravity outright, so a coin never drifts away from
	# a player who is already reaching for it. Never overshoot the player.
	global_position += (to_player / distance) * minf(magnet_speed * delta, distance)
	if distance < COLLECT_DISTANCE:
		_collect()
	return true


func _fall(delta: float) -> void:
	_velocity.y = minf(_velocity.y + fall_gravity * delta, max_fall_speed)
	_velocity.x = move_toward(_velocity.x, 0.0, 420.0 * delta)
	global_position += _velocity * delta
	if _velocity.y <= 0.0:
		return
	# Land on the first solid surface below instead of falling out of the world.
	ground_probe.force_raycast_update()
	if ground_probe.is_colliding():
		global_position.y = ground_probe.get_collision_point().y - COIN_RADIUS
		_velocity = Vector2.ZERO
		_falling = false


func _collect() -> void:
	GameManager.add_currency(value)
	Sfx.play_chain("coin", 0.8)
	Juice.coin_sparkle(global_position)
	queue_free()


func _on_body_entered(body: Node2D) -> void:
	if body is Player and _collect_delay <= 0.0:
		_collect()
