extends Area2D
## Base weapon projectile. Pooled — never freed during gameplay (§30).
## Charged shots pierce light enemies (§7).

@export var speed: float = 900.0
@export var lifetime: float = 1.2

var direction: int = 1
var damage: int = 10
var pierce: bool = false
var life_timer: float = 0.0
var pool: Node = null


func launch(from: Vector2, dir: int, dmg: int, is_pierce: bool) -> void:
	global_position = from
	direction = dir
	damage = dmg
	pierce = is_pierce
	life_timer = lifetime
	scale = Vector2.ONE * (1.6 if pierce else 1.0)
	visible = true
	set_deferred("monitoring", true)
	set_physics_process(true)


func _physics_process(delta: float) -> void:
	position.x += direction * speed * delta
	life_timer -= delta
	if life_timer <= 0.0:
		_despawn()


func _on_body_entered(body: Node2D) -> void:
	if body.has_method("take_damage"):
		body.take_damage(damage)
		if pierce:
			return
	_despawn()


func _despawn() -> void:
	visible = false
	set_deferred("monitoring", false)
	set_physics_process(false)
	if pool:
		pool.release(self)
