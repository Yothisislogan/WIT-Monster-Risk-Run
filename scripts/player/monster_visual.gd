extends Node2D
## The WIT Monster's face and body. Procedural rather than sprite-based, so it
## can react continuously: pupils track movement, it blinks, it opens its mouth
## on the way up and grits it on the way down, and it leans into a run.
##
## Prototype acceptance criterion §32.10 is "the Monster's personality is
## visible through animation alone" — that is what this file is for.

@export var lean_degrees: float = 9.0
@export var bob_amount: float = 1.6

@onready var pupil_left: Polygon2D = $PupilLeft
@onready var pupil_right: Polygon2D = $PupilRight
@onready var lid_left: Polygon2D = $LidLeft
@onready var lid_right: Polygon2D = $LidRight
@onready var mouth: Polygon2D = $Mouth
@onready var body: Polygon2D = $Body

var _player: CharacterBody2D = null
var _age: float = 0.0
var _blink_timer: float = 2.0
var _blink: float = 0.0
var _pupil_home_left: Vector2
var _pupil_home_right: Vector2
var _mouth_home: Vector2


func _ready() -> void:
	_player = get_parent() as CharacterBody2D
	_pupil_home_left = pupil_left.position
	_pupil_home_right = pupil_right.position
	_mouth_home = mouth.position
	_blink_timer = randf_range(1.5, 4.0)


func _process(delta: float) -> void:
	if _player == null:
		return
	_age += delta
	var velocity: Vector2 = _player.velocity
	var grounded: bool = _player.is_on_floor()
	var speed_ratio := clampf(absf(velocity.x) / 360.0, 0.0, 1.0)

	# Lean into the run, straighten in the air. The lean is always forward in
	# local space — the parent already mirrors scale.x by facing, and applying
	# the sign here too would lean backwards when running left.
	var target_lean := deg_to_rad(lean_degrees) * speed_ratio
	if not grounded:
		target_lean *= 0.4
	rotation = lerp_angle(rotation, target_lean, 1.0 - exp(-12.0 * delta))

	# Running bob, only while actually moving on the ground.
	var bob := 0.0
	if grounded and speed_ratio > 0.1:
		bob = sin(_age * 18.0 * speed_ratio) * bob_amount * speed_ratio
	body.position.y = bob

	_update_eyes(delta, velocity, grounded)
	_update_mouth(delta, velocity, grounded)


func _update_eyes(delta: float, velocity: Vector2, grounded: bool) -> void:
	# Pupils lead the movement — the cheapest way to make a face look alive.
	var facing: int = _player.facing if "facing" in _player else 1
	var look := Vector2(clampf(velocity.x / 400.0, -1.0, 1.0) * facing,
			clampf(velocity.y / 700.0, -1.0, 1.0)) * 2.6
	pupil_left.position = pupil_left.position.lerp(
			_pupil_home_left + look, 1.0 - exp(-14.0 * delta))
	pupil_right.position = pupil_right.position.lerp(
			_pupil_home_right + look, 1.0 - exp(-14.0 * delta))

	_blink_timer -= delta
	if _blink_timer <= 0.0:
		_blink_timer = randf_range(2.0, 5.5)
		_blink = 1.0
	_blink = maxf(_blink - delta * 7.0, 0.0)
	# Eyes also narrow when falling fast: reads as bracing for impact.
	var squint := _blink
	if not grounded and velocity.y > 500.0:
		squint = maxf(squint, 0.55)
	lid_left.scale.y = squint
	lid_right.scale.y = squint


func _update_mouth(delta: float, velocity: Vector2, grounded: bool) -> void:
	var open := 0.0
	if not grounded:
		# Mouth opens on the way up, clamps shut on the way down.
		open = clampf(-velocity.y / 600.0, 0.0, 1.0)
	mouth.scale.y = lerp(mouth.scale.y, 1.0 + open * 1.6, 1.0 - exp(-12.0 * delta))
	mouth.position.y = lerp(mouth.position.y, _mouth_home.y + open * 2.0,
			1.0 - exp(-12.0 * delta))
