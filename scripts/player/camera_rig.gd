extends Camera2D
## Look-ahead camera (GAME_DESIGN.md §17): drifts toward the player's facing
## direction so upcoming hazards are visible on a small landscape screen.
## Also applies the shared screen shake so shake composes with look-ahead.

@export var look_ahead_distance: float = 130.0
@export var look_ahead_speed: float = 3.0
## Subtle drop when falling fast, so big landings read as heavy.
@export var fall_look_down: float = 70.0

@onready var player: Player = get_parent()

var _base_offset: Vector2 = Vector2.ZERO


func _ready() -> void:
	Juice.register_camera(self)


func _process(delta: float) -> void:
	var target := Vector2(player.facing * look_ahead_distance, 0.0)
	# Look down while falling fast; the player should see where they land.
	if player.velocity.y > 300.0:
		target.y = fall_look_down * clampf(player.velocity.y / 1000.0, 0.0, 1.0)
	_base_offset = _base_offset.lerp(target, 1.0 - exp(-look_ahead_speed * delta))
	offset = _base_offset + Juice.shake_offset()
