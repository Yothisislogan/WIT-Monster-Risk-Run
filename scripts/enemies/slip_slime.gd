extends EnemyBase
## Slip-and-Fall Slime (Liability Land, §16). Hops toward you in a slow arc
## and leaves the floor slick where it lands. Reads as harmless, is not.

@export var hop_interval: float = 1.5
@export var hop_velocity: Vector2 = Vector2(180.0, -430.0)
@export var gravity: float = 1500.0

@onready var visual: Node2D = $Visual

var _timer: float = 0.0
var _player: Player = null
var _facing: int = -1


func _ready() -> void:
	super._ready()
	_timer = randf() * hop_interval
	var players := get_tree().get_nodes_in_group("player")
	if not players.is_empty():
		_player = players[0]


func _physics_process(delta: float) -> void:
	velocity.y += gravity * delta
	if is_on_floor():
		velocity.x = move_toward(velocity.x, 0.0, 700.0 * delta)
		_timer -= delta
		# Squash right before the hop: the whole tell in one shape change.
		var crouch := clampf(1.0 - _timer / 0.35, 0.0, 1.0)
		visual.scale = Vector2(1.0 + 0.3 * crouch, 1.0 - 0.3 * crouch)
		if _timer <= 0.0:
			_hop()
	else:
		visual.scale = visual.scale.lerp(Vector2(0.85, 1.2), 1.0 - exp(-8.0 * delta))
	visual.scale.x = absf(visual.scale.x) * -_facing
	move_and_slide()


func _hop() -> void:
	_timer = hop_interval
	if is_instance_valid(_player):
		_facing = 1 if _player.global_position.x > global_position.x else -1
	velocity = Vector2(hop_velocity.x * _facing, hop_velocity.y)
	Sfx.play("bounce", 0.2, 0.45)
	Juice.dust(global_position + Vector2(0.0, 18.0), 5)


func _on_damaged() -> void:
	super._on_damaged()
	visual.modulate = Color(3.0, 3.0, 3.0)
	var tween := create_tween()
	tween.tween_property(visual, "modulate", Color.WHITE, 0.14)
