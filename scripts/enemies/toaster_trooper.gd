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


func _on_damaged() -> void:
	visual.modulate = Color(3.0, 3.0, 3.0)
	var tween := create_tween()
	tween.tween_property(visual, "modulate", Color.WHITE, 0.15)
