extends CanvasLayer
## Touch control layer. Visible only on touch devices; desktop and controller
## players never see it (GAME_DESIGN.md §6, §22).
##
## There are no buttons any more. The left 46% of the screen is a floating
## movement stick that anchors wherever the thumb lands, and the right side is
## a gesture surface — see scripts/ui/gesture_controls.gd for the mapping.
## Seven buttons used to sit on top of a landscape playfield; now nothing does
## except a stick that only draws while it is being held.

@onready var root: Control = $Root
@onready var stick: Control = $Root/VirtualStick
@onready var gestures: Control = $Root/GestureArea

## Anchors and offsets exactly as authored. Left-handed play mirrors these
## rather than the current values, so re-applying settings cannot flip an
## already-mirrored layout back.
var _base_layout: Dictionary = {}
var _paused: bool = false


func _ready() -> void:
	visible = DisplayServer.is_touchscreen_available()
	# Touch input must survive the pause, or the two-finger pause gesture is
	# the one control you cannot use once you have used it.
	process_mode = Node.PROCESS_MODE_ALWAYS
	_capture_base_layout()
	Settings.changed.connect(_on_setting_changed)
	_apply_settings()


## Controls go away while the game is paused. That is not only tidy:
## Input.action_press latches until something releases it, and the auto-pause
## on focus-out (GameManager._notification) fires while a thumb is still down.
## Hiding them trips the visibility guards in virtual_stick and
## gesture_controls, which release rather than leaving an action held through
## the resume.
func _process(_delta: float) -> void:
	var paused := get_tree().paused
	if paused == _paused:
		return
	_paused = paused
	stick.visible = not paused
	# The gesture surface stays live so a second two-finger tap un-pauses.
	gestures.visible = true


func _capture_base_layout() -> void:
	for child in root.get_children():
		if child is Control:
			var control: Control = child
			_base_layout[control.name] = {
				"anchor_left": control.anchor_left,
				"anchor_right": control.anchor_right,
				"offset_left": control.offset_left,
				"offset_right": control.offset_right,
			}


func _on_setting_changed(key: String, _value: Variant) -> void:
	if key in ["control_opacity", "control_scale", "left_handed"]:
		_apply_settings()


## Opacity, size and handedness are all §22 requirements. With the buttons
## gone, scale no longer has anything to resize — the stick sizes itself to the
## thumb — so only opacity and handedness still do work here.
func _apply_settings() -> void:
	root.modulate.a = clampf(float(Settings.get_value("control_opacity")), 0.15, 1.0)
	var mirrored := bool(Settings.get_value("left_handed"))
	for child in root.get_children():
		if not child is Control:
			continue
		var control: Control = child
		var base: Dictionary = _base_layout.get(control.name, {})
		if base.is_empty():
			continue
		# Left-handed play swaps which side moves and which side acts.
		if mirrored:
			control.anchor_left = 1.0 - float(base["anchor_right"])
			control.anchor_right = 1.0 - float(base["anchor_left"])
			control.offset_left = -float(base["offset_right"])
			control.offset_right = -float(base["offset_left"])
		else:
			control.anchor_left = float(base["anchor_left"])
			control.anchor_right = float(base["anchor_right"])
			control.offset_left = float(base["offset_left"])
			control.offset_right = float(base["offset_right"])
