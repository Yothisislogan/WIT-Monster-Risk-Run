extends CanvasLayer
## Touch control layer. Visible only on touch devices; desktop and
## controller players never see it. Opacity comes from saved settings so
## players can tune it later (GAME_DESIGN.md §6, §22).

@onready var root: Control = $Root
@onready var cycle_button: Control = $Root/CycleButton

## Anchors and offsets exactly as authored. Left-handed play mirrors these
## rather than the current values, so re-applying settings cannot flip an
## already-mirrored layout back.
var _base_layout: Dictionary = {}


func _ready() -> void:
	visible = DisplayServer.is_touchscreen_available()
	_capture_base_layout()
	Settings.changed.connect(_on_setting_changed)
	_apply_settings()
	# The swap button only earns its screen space once there is a second
	# ability to swap to (§14).
	Events.ability_granted.connect(func(_id: String) -> void: _refresh_cycle_button())
	Events.run_started.connect(_refresh_cycle_button)
	_refresh_cycle_button()


func _refresh_cycle_button() -> void:
	cycle_button.visible = GameManager.abilities.size() > 1


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


## Size, opacity and handedness are all §22 requirements.
func _apply_settings() -> void:
	root.modulate.a = clampf(float(Settings.get_value("control_opacity")), 0.15, 1.0)
	var scale_factor := clampf(float(Settings.get_value("control_scale")), 0.6, 1.6)
	var mirrored := bool(Settings.get_value("left_handed"))
	for child in root.get_children():
		if not child is Control:
			continue
		var control: Control = child
		control.scale = Vector2(scale_factor, scale_factor)
		control.pivot_offset = control.size * 0.5
		var base: Dictionary = _base_layout.get(control.name, {})
		if base.is_empty():
			continue
		# Left-handed play mirrors the stick and the buttons across the screen.
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
