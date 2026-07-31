extends AnimatableBody2D
## Moving platform. AnimatableBody2D with sync_to_physics enabled is the one
## approach in Godot 4 that carries a CharacterBody2D correctly — do not
## swap this for a StaticBody2D moved in _process, the player will slide off.

@export var travel: Vector2 = Vector2(220.0, 0.0)
@export var duration: float = 2.4
@export var pause_time: float = 0.35
## Stagger identical platforms so a row of them does not move in lockstep.
@export var start_offset: float = 0.0

var _origin: Vector2 = Vector2.ZERO


func _ready() -> void:
	sync_to_physics = true
	_origin = position
	_start_loop()


func _start_loop() -> void:
	var tween := create_tween().set_loops()
	tween.set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN_OUT)
	if start_offset > 0.0:
		tween.tween_interval(start_offset)
	tween.tween_property(self, "position", _origin + travel, duration)
	tween.tween_interval(pause_time)
	tween.tween_property(self, "position", _origin, duration)
	tween.tween_interval(pause_time)
