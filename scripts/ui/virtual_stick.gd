extends Control
## Floating virtual movement stick (GAME_DESIGN.md §6): the stick anchors
## wherever the thumb lands inside this control's area, so hand position is
## never forced. Emits analog strength through the shared input actions.

@export var stick_radius: float = 90.0
@export var dead_zone: float = 0.25
@export var vertical_threshold: float = 0.5

const HORIZONTAL_ACTIONS: Array[StringName] = [&"move_left", &"move_right"]
const VERTICAL_ACTIONS: Array[StringName] = [&"move_up", &"move_down"]

var _touch_index: int = -1
var _origin: Vector2 = Vector2.ZERO
var _vector: Vector2 = Vector2.ZERO


func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE


func _input(event: InputEvent) -> void:
	if event is InputEventScreenTouch:
		if event.pressed and _touch_index == -1 and get_global_rect().has_point(event.position):
			_touch_index = event.index
			_origin = event.position
			_update(event.position)
		elif not event.pressed and event.index == _touch_index:
			_release()
	elif event is InputEventScreenDrag and event.index == _touch_index:
		_update(event.position)


func _update(screen_position: Vector2) -> void:
	_vector = ((screen_position - _origin) / stick_radius).limit_length(1.0)
	_apply_axis(_vector.x, HORIZONTAL_ACTIONS, dead_zone)
	_apply_axis(_vector.y, VERTICAL_ACTIONS, vertical_threshold)
	queue_redraw()


func _apply_axis(value: float, actions: Array[StringName], threshold: float) -> void:
	if value < -threshold:
		Input.action_press(actions[0], -value)
		Input.action_release(actions[1])
	elif value > threshold:
		Input.action_press(actions[1], value)
		Input.action_release(actions[0])
	else:
		Input.action_release(actions[0])
		Input.action_release(actions[1])


func _release() -> void:
	_touch_index = -1
	_vector = Vector2.ZERO
	for action in HORIZONTAL_ACTIONS + VERTICAL_ACTIONS:
		Input.action_release(action)
	queue_redraw()


func _draw() -> void:
	if _touch_index == -1:
		return
	var local_origin := _origin - global_position
	draw_circle(local_origin, stick_radius, Color(1, 1, 1, 0.08))
	draw_arc(local_origin, stick_radius, 0.0, TAU, 48, Color(1, 1, 1, 0.25), 2.0)
	draw_circle(local_origin + _vector * stick_radius * 0.6, 34.0, Color(0.12, 0.48, 0.88, 0.6))
