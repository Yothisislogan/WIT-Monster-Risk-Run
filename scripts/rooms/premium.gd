extends Area2D
## "Premium" — the collectible coin. Arcs out of crates and enemies, settles,
## then magnetises to the Monster so collection always feels generous.

@export var value: int = 1
@export var magnet_radius: float = 130.0
@export var magnet_speed: float = 900.0
@export var gravity: float = 1400.0
@export var lifetime: float = 22.0

@onready var visual: Node2D = $Visual

var _velocity: Vector2 = Vector2.ZERO
var _settled: bool = false
var _age: float = 0.0
var _collect_delay: float = 0.25
var _player: Player = null


func _ready() -> void:
	var players := get_tree().get_nodes_in_group("player")
	if not players.is_empty():
		_player = players[0]


func pop(impulse: Vector2) -> void:
	_velocity = impulse
	_settled = false


func _physics_process(delta: float) -> void:
	_age += delta
	_collect_delay = maxf(_collect_delay - delta, 0.0)
	if _age > lifetime:
		queue_free()
		return

	# Idle bob so a resting Premium still catches the eye on a small screen.
	visual.position.y = sin(_age * 5.0) * 3.0
	visual.rotation = sin(_age * 3.0) * 0.35

	if is_instance_valid(_player) and _collect_delay <= 0.0:
		var to_player := _player.global_position - global_position
		if to_player.length() < magnet_radius:
			# Magnet beats physics entirely — no fighting gravity near the player.
			_velocity = to_player.normalized() * magnet_speed
			_settled = false
			position += _velocity * delta
			if to_player.length() < 26.0:
				_collect()
			return

	if not _settled:
		_velocity.y += gravity * delta
		_velocity.x = move_toward(_velocity.x, 0.0, 420.0 * delta)
		position += _velocity * delta


func _collect() -> void:
	GameManager.add_currency(value)
	Juice.coin_sparkle(global_position)
	queue_free()


func _on_body_entered(body: Node2D) -> void:
	if body is Player and _collect_delay <= 0.0:
		_collect()
