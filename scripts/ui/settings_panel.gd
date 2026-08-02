extends PanelContainer
## Settings, covering the accessibility options the design doc requires (§22).
## Rows are built in code so adding an option is one line rather than a pile
## of scene nodes. Instanced by both the title screen and the pause menu.

signal closed

const OPTIONS := [
	{"key": "music_volume", "label": "Music volume", "type": "slider", "default": 0.7},
	{"key": "sfx_volume", "label": "Effects volume", "type": "slider", "default": 0.8},
	{"key": "control_scale", "label": "Touch control size", "type": "slider",
	 "default": 1.0, "min": 0.7, "max": 1.5},
	{"key": "control_opacity", "label": "Touch control opacity", "type": "slider",
	 "default": 1.0, "min": 0.2, "max": 1.0},
	{"key": "left_handed", "label": "Left-handed layout", "type": "toggle", "default": false},
	{"key": "reduced_shake", "label": "Reduce screen shake", "type": "toggle", "default": false},
	{"key": "reduced_flashing", "label": "Reduce flashing", "type": "toggle", "default": false},
	{"key": "auto_fire", "label": "Auto-fire", "type": "toggle", "default": false},
	{"key": "game_speed", "label": "Game speed", "type": "slider",
	 "default": 1.0, "min": 0.6, "max": 1.0},
]

@onready var rows: VBoxContainer = $Margin/VBox/Rows
@onready var close_button: Button = $Margin/VBox/CloseButton


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	close_button.pressed.connect(func() -> void:
		Sfx.play("ui_confirm")
		closed.emit())
	_build()


func _build() -> void:
	for child in rows.get_children():
		child.queue_free()
	for option in OPTIONS:
		rows.add_child(_build_row(option))


func _build_row(option: Dictionary) -> Control:
	var row := HBoxContainer.new()
	row.custom_minimum_size = Vector2(0, 46)
	row.add_theme_constant_override("separation", 16)

	var label := Label.new()
	label.text = String(option["label"])
	label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	label.add_theme_font_size_override("font_size", 18)
	row.add_child(label)

	var key := String(option["key"])
	if String(option["type"]) == "toggle":
		var button := Button.new()
		button.custom_minimum_size = Vector2(150, 42)
		button.toggle_mode = true
		button.button_pressed = bool(Settings.get_value(key, option["default"]))
		button.text = "ON" if button.button_pressed else "OFF"
		button.toggled.connect(func(pressed: bool) -> void:
			button.text = "ON" if pressed else "OFF"
			Sfx.play("ui_move")
			Settings.set_value(key, pressed))
		row.add_child(button)
	else:
		var value := float(Settings.get_value(key, option["default"]))
		var readout := Label.new()
		readout.custom_minimum_size = Vector2(64, 0)
		readout.add_theme_font_size_override("font_size", 17)
		readout.text = "%d%%" % int(round(value * 100.0))

		var slider := HSlider.new()
		slider.custom_minimum_size = Vector2(260, 42)
		slider.min_value = float(option.get("min", 0.0))
		slider.max_value = float(option.get("max", 1.0))
		slider.step = 0.05
		slider.value = value
		slider.value_changed.connect(func(v: float) -> void:
			readout.text = "%d%%" % int(round(v * 100.0))
			Settings.set_value(key, v))
		row.add_child(slider)
		row.add_child(readout)
	return row
