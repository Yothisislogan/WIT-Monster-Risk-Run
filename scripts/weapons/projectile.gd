extends Area2D
## Base weapon projectile. Pooled — never freed during gameplay (§30).
## Charged shots pierce light enemies (§7).

@export var speed: float = 900.0
@export var lifetime: float = 1.2

## A unit vector, not a sign. §6 asks for vertical aim and mild correction
## toward nearby enemies, neither of which a horizontal-only shot can do —
## and without it the Ember Imp, the only flying peril, is unhittable.
var direction: Vector2 = Vector2.RIGHT
var damage: int = 10
var pierce: bool = false
var life_timer: float = 0.0
var pool: Node = null
## `monitoring` is cleared with set_deferred, so a shot that overlaps two
## bodies in one physics flush gets body_entered twice and would be released
## into the pool twice — after which two shots share one node.
var _active: bool = false


func launch(from: Vector2, dir: Vector2, dmg: int, is_pierce: bool) -> void:
	_active = true
	global_position = from
	direction = dir.normalized() if dir.length_squared() > 0.0 else Vector2.RIGHT
	damage = dmg
	pierce = is_pierce
	life_timer = lifetime
	# Both projectile visuals are drawn pointing along +X, so the whole node
	# can just be rotated to face travel.
	rotation = direction.angle()
	scale = Vector2.ONE * (1.6 if pierce else 1.0)
	visible = true
	set_deferred("monitoring", true)
	set_physics_process(true)


func _physics_process(delta: float) -> void:
	position += direction * speed * delta
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
	if not _active:
		return
	_active = false
	visible = false
	set_deferred("monitoring", false)
	set_physics_process(false)
	if pool:
		pool.release(self)
