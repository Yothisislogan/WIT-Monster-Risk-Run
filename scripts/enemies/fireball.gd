extends Area2D
## Boss projectile. Big, slow and loud enough to read on a phone (§16):
## limited counts, high contrast, and a visible arc rather than a hitscan.

@export var damage: int = 12
@export var lifetime: float = 4.0
## Not `gravity`: Area2D declares one natively and redefining it is a
## parse error that stops the scene loading.
@export var fall_gravity: float = 0.0

var velocity: Vector2 = Vector2.ZERO
var _age: float = 0.0

@onready var visual: Node2D = $Visual


func launch(from: Vector2, initial_velocity: Vector2, dmg: int, grav: float = 0.0) -> void:
	global_position = from
	velocity = initial_velocity
	damage = dmg
	fall_gravity = grav
	_age = 0.0


func _physics_process(delta: float) -> void:
	_age += delta
	if _age > lifetime:
		queue_free()
		return
	velocity.y += fall_gravity * delta
	global_position += velocity * delta
	visual.rotation += 9.0 * delta
	# Pulse so it stays legible against a busy background.
	var pulse := 1.0 + sin(_age * 22.0) * 0.12
	visual.scale = Vector2(pulse, pulse)


func _on_body_entered(body: Node2D) -> void:
	if body is Player:
		body.hurt(damage, "cooked by the Inferno Adjuster")
		_burst()


func _on_area_entered(area: Area2D) -> void:
	# A charged shot or Flame Draft can swat a fireball out of the air.
	if area.get_collision_layer_value(4):
		_burst()


func _burst() -> void:
	Juice.enemy_death(global_position, Color(1.0, 0.6, 0.2))
	Sfx.play("enemy_hit", 0.15, 0.7)
	queue_free()
