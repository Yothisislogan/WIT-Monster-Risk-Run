extends EnemyBase
## Toaster Trooper: the prototype's basic patrol enemy (§16). Walks a ledge,
## turns at edges and walls. Predictable, readable, strong silhouette.

@export var walk_speed: float = 80.0
@export var gravity: float = 1500.0

var direction: int = -1

@onready var edge_probe: RayCast2D = $EdgeProbe
@onready var visual: Node2D = $Visual


func _physics_process(delta: float) -> void:
	if not is_on_floor():
		velocity.y += gravity * delta
	else:
		# Turn around at walls and ledge edges.
		if is_on_wall() or not edge_probe.is_colliding():
			direction *= -1
			edge_probe.position.x = absf(edge_probe.position.x) * direction
		velocity.x = direction * walk_speed
	visual.scale.x = absf(visual.scale.x) * -direction
	move_and_slide()


var _base_tint := Color.WHITE


func _on_damaged() -> void:
	super._on_damaged()
	visual.modulate = Color(3.0, 3.0, 3.0)
	visual.scale = Vector2(1.25, 0.78)
	var tween := create_tween()
	tween.tween_property(visual, "modulate", _base_tint, 0.15)
	tween.parallel().tween_property(visual, "scale", Vector2.ONE, 0.18)


func _on_weakened() -> void:
	# Green tint signals "munchable" — readable at a glance on a phone.
	_base_tint = Color(0.6, 1.0, 0.65)


func _on_burn_changed(burning: bool) -> void:
	if burning:
		_base_tint = Color(1.0, 0.55, 0.3)
	else:
		_base_tint = Color(0.6, 1.0, 0.65) if weakened else Color.WHITE
	visual.modulate = _base_tint
