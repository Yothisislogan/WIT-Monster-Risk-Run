extends AnimatableBody2D
## Collapsing platform (Blaze Borough, §12). Shakes for a beat when you stand
## on it, falls, then rebuilds. The tell is generous because on a phone you
## cannot afford surprise floor loss (§17 "limit blind jumps").

@export var warn_time: float = 0.55
@export var fall_speed: float = 900.0
@export var respawn_time: float = 2.6

@onready var visual: Node2D = $Visual
@onready var collision: CollisionShape2D = $Shape
@onready var detector: Area2D = $Detector

enum State { SOLID, WARNING, FALLING, GONE }

var _state: int = State.SOLID
var _timer: float = 0.0
var _origin: Vector2 = Vector2.ZERO


func _ready() -> void:
	sync_to_physics = true
	_origin = position


func _physics_process(delta: float) -> void:
	match _state:
		State.SOLID:
			for body in detector.get_overlapping_bodies():
				if body is Player:
					_state = State.WARNING
					_timer = warn_time
					Sfx.play("ui_move", 0.2, 0.6)
					break
		State.WARNING:
			_timer -= delta
			# Shake harder as it is about to go.
			var urgency := 1.0 - _timer / warn_time
			visual.position.x = sin(_timer * 60.0) * 3.0 * urgency
			visual.modulate = Color.WHITE.lerp(Color(1.6, 0.8, 0.6), urgency)
			if _timer <= 0.0:
				_state = State.FALLING
				_timer = 1.4
				collision.set_deferred("disabled", true)
				Juice.dust(global_position, 10)
				Sfx.play("crate_break", 0.15, 0.7)
		State.FALLING:
			position.y += fall_speed * delta
			_timer -= delta
			visual.modulate.a = maxf(_timer / 1.4, 0.0)
			if _timer <= 0.0:
				_state = State.GONE
				_timer = respawn_time
				visible = false
		State.GONE:
			_timer -= delta
			if _timer <= 0.0:
				_reset()


func _reset() -> void:
	_state = State.SOLID
	position = _origin
	visible = true
	visual.position = Vector2.ZERO
	visual.modulate = Color.WHITE
	collision.set_deferred("disabled", false)
