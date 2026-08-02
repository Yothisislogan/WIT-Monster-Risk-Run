extends CanvasLayer
## Touch control layer. Visible only on touch devices; desktop and
## controller players never see it. Opacity comes from saved settings so
## players can tune it later (GAME_DESIGN.md §6, §22).

@onready var root: Control = $Root


func _ready() -> void:
	visible = DisplayServer.is_touchscreen_available()
	Settings.changed.connect(_on_setting_changed)
	_apply_settings()


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
		# Left-handed play mirrors the stick and the buttons across the screen.
		if mirrored:
			control.anchor_left = 1.0 - control.anchor_left
			control.anchor_right = 1.0 - control.anchor_right
			var left := control.offset_left
			control.offset_left = -control.offset_right
			control.offset_right = -left
