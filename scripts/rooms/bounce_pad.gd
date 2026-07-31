extends Area2D
## "Actuarial Trampoline" — a claims-adjuster mattress that launches the
## Monster skyward. Re-triggers on contact so chained bounces feel great,
## and a ground pound compresses it for a much bigger launch (§14 combos).

@export var launch_force: float = 900.0
@export var pound_bonus: float = 1.6

@onready var pad: Polygon2D = $Pad

var _cooldown: float = 0.0
var _rest_scale: Vector2 = Vector2.ONE


func _ready() -> void:
	_rest_scale = pad.scale


func _physics_process(delta: float) -> void:
	_cooldown = maxf(_cooldown - delta, 0.0)
	pad.scale = pad.scale.lerp(_rest_scale, 1.0 - exp(-12.0 * delta))
	if _cooldown > 0.0:
		return
	for body in get_overlapping_bodies():
		if body is Player and body.velocity.y >= -10.0:
			_launch(body)
			return


func _launch(player: Player) -> void:
	var force := launch_force
	if player.pounding:
		# Slamming into the pad converts downward force into a huge pop.
		force *= pound_bonus
	_cooldown = 0.12
	pad.scale = _rest_scale * Vector2(1.25, 0.35)
	player.launch(force)
	Juice.dust(global_position, 10)
