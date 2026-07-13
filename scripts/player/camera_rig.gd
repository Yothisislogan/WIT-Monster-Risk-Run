extends Camera2D
## Look-ahead camera (GAME_DESIGN.md §17): drifts toward the player's facing
## direction so upcoming hazards are visible on a small landscape screen.

@export var look_ahead_distance: float = 120.0
@export var look_ahead_speed: float = 3.0

@onready var player: Player = get_parent()


func _process(delta: float) -> void:
	var target_offset := Vector2(player.facing * look_ahead_distance, 0.0)
	offset = offset.lerp(target_offset, 1.0 - exp(-look_ahead_speed * delta))
