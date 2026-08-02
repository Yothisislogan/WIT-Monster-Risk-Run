extends Area2D
## Oil slick (Crashway 5000, §12). Does no damage — it steals your grip, which
## on a phone is scarier than a damage tick and never feels unfair.

@export var friction_scale: float = 0.15
@export var accel_scale: float = 0.45

@onready var visual: Polygon2D = $Visual

var _age: float = 0.0


func _physics_process(delta: float) -> void:
	_age += delta
	visual.modulate.a = 0.75 + sin(_age * 2.4) * 0.12
	for body in get_overlapping_bodies():
		if body is Player:
			body.apply_surface(friction_scale, accel_scale)
