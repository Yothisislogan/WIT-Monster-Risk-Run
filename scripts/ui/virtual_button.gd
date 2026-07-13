extends Control
## On-screen action button. Feeds the same input actions as keyboard and
## controller (GAME_DESIGN.md §6, §30). Tracks its own touch index so any
## number of buttons can be held at once (jump + attack must both register).

@export var action: StringName = &"jump"
@export var label_text: String = "JUMP"
@export var button_color: Color = Color(0.12, 0.48, 0.88, 0.55)
@export var pressed_color: Color = Color(0.12, 0.48, 0.88, 0.9)

var _touch_index: int = -1


func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE  # raw touch handling below


func _input(event: InputEvent) -> void:
	if event is InputEventScreenTouch:
		if event.pressed and _touch_index == -1 and _inside(event.position):
			_touch_index = event.index
			Input.action_press(action)
			queue_redraw()
		elif not event.pressed and event.index == _touch_index:
			_release()
	elif event is InputEventScreenDrag and event.index == _touch_index:
		# Sliding a finger off the button releases it.
		if not _inside(event.position):
			_release()


func _release() -> void:
	_touch_index = -1
	Input.action_release(action)
	queue_redraw()


func _inside(screen_position: Vector2) -> bool:
	return get_global_rect().has_point(screen_position)


func _draw() -> void:
	var radius := minf(size.x, size.y) * 0.5
	var center := size * 0.5
	draw_circle(center, radius, pressed_color if _touch_index != -1 else button_color)
	var font := get_theme_default_font()
	var font_size := 18
	var text_size := font.get_string_size(label_text, HORIZONTAL_ALIGNMENT_CENTER, -1, font_size)
	draw_string(font, center + Vector2(-text_size.x * 0.5, text_size.y * 0.3), label_text,
			HORIZONTAL_ALIGNMENT_CENTER, -1, font_size, Color(1, 1, 1, 0.9))
