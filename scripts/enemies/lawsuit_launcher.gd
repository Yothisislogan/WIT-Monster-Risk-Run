extends EnemyBase
## Lawsuit Launcher (§16 ranged role). Stationary, armoured from the front,
## lobs a slow subpoena on a long telegraph. It exists to punish standing
## still and to reward closing the distance with a dash.

@export var projectile_scene: PackedScene
@export var detect_range: float = 520.0
@export var telegraph_time: float = 0.85
@export var reload_time: float = 1.9
@export var projectile_damage: int = 10
@export var projectile_speed: float = 260.0

@onready var visual: Node2D = $Visual
@onready var barrel: Node2D = $Visual/Barrel

var _cooldown: float = 0.0
var _telegraph: float = 0.0
var _player: Player = null
var _facing: int = -1


func _ready() -> void:
	super._ready()
	var players := get_tree().get_nodes_in_group("player")
	if not players.is_empty():
		_player = players[0]


func _physics_process(delta: float) -> void:
	velocity.y += 1500.0 * delta
	move_and_slide()

	if not is_instance_valid(_player):
		return
	var to_player := _player.global_position - global_position
	_facing = 1 if to_player.x > 0.0 else -1
	visual.scale.x = absf(visual.scale.x) * _facing

	if _telegraph > 0.0:
		_telegraph -= delta
		# Barrel rises and glows through the whole wind-up.
		var t := 1.0 - _telegraph / telegraph_time
		barrel.rotation = lerp(0.0, -0.5, t) * _facing
		barrel.modulate = Color(1, 1, 1).lerp(Color(2.4, 1.6, 1.6), t)
		if _telegraph <= 0.0:
			_fire(to_player)
		return

	barrel.rotation = move_toward(barrel.rotation, 0.0, 2.0 * delta)
	barrel.modulate = Color.WHITE
	_cooldown = maxf(_cooldown - delta, 0.0)
	if _cooldown <= 0.0 and to_player.length() < detect_range:
		_telegraph = telegraph_time
		Sfx.play("ui_move", 0.15, 0.5)


func _fire(to_player: Vector2) -> void:
	# The launcher escalates by firing more often, not by firing faster. The
	# lob arc is a design property — "you can walk under it or dash through the
	# gap" — and speeding the projectile up would quietly delete that.
	_cooldown = reload_time / speed_factor
	if projectile_scene == null:
		return
	var direction := to_player.normalized()
	var shot: Node2D = projectile_scene.instantiate()
	get_parent().add_child(shot)
	# Lobbed, not hitscan: you can walk under it or dash through the gap.
	shot.launch(global_position + direction * 34.0,
			direction * projectile_speed + Vector2(0.0, -110.0),
			projectile_damage, 420.0)
	Sfx.play("shoot", 0.1, 0.8)
	Juice.shake(2.0, 0.12)


func _on_damaged() -> void:
	super._on_damaged()
	visual.modulate = Color(3.0, 3.0, 3.0)
	var tween := create_tween()
	tween.tween_property(visual, "modulate", Color.WHITE, 0.14)
	# Getting shot mid-wind-up spoils the shot — rewards reacting to the tell.
	if _telegraph > 0.0:
		_telegraph = 0.0
		_cooldown = reload_time * 0.6
