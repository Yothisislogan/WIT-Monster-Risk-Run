extends Control
## Title screen and run setup. A returning player with a saved run sees
## CONTINUE first; a new player sees the deductible choice, which is where
## difficulty is actually selected (GAME_DESIGN.md §8, §23).

const GAME_SCENE := "res://scenes/main.tscn"

@onready var menu: VBoxContainer = %Menu
@onready var deductible_panel: PanelContainer = %DeductiblePanel
@onready var deductible_rows: VBoxContainer = %DeductibleRows
@onready var settings_panel: PanelContainer = %SettingsPanel
@onready var record_label: Label = %RecordLabel


func _ready() -> void:
	Settings.apply_all()
	settings_panel.visible = false
	deductible_panel.visible = false
	settings_panel.closed.connect(func() -> void:
		settings_panel.visible = false
		menu.visible = true)
	_build_menu()
	_build_deductibles()
	_show_record()
	MusicManager.play("blaze_borough")


func _show_record() -> void:
	var lifetime: Dictionary = SaveManager.get_section("stats")
	var runs := int(lifetime.get("runs", 0))
	if runs == 0:
		record_label.text = "No claims on file."
		return
	record_label.text = "Claims filed: %d     Survived: %d     Worst loss: $%s" % [
		runs, int(lifetime.get("wins", 0)),
		ClaimReport.money(int(lifetime.get("best_property_damage", 0)))]


func _build_menu() -> void:
	for child in menu.get_children():
		child.queue_free()
	if SaveManager.has_resumable_run():
		menu.add_child(_button("CONTINUE RUN", _on_continue))
	menu.add_child(_button("NEW POLICY", _on_new_policy))
	menu.add_child(_button("OPTIONS", _on_options))


func _button(text: String, handler: Callable) -> Button:
	var button := Button.new()
	button.text = text
	button.custom_minimum_size = Vector2(360, 62)
	button.add_theme_font_size_override("font_size", 22)
	button.pressed.connect(handler)
	return button


func _build_deductibles() -> void:
	for child in deductible_rows.get_children():
		child.queue_free()
	for key in ["low", "standard", "high"]:
		var preset: Dictionary = GameManager.DEDUCTIBLES[key]
		var button := Button.new()
		button.custom_minimum_size = Vector2(0, 88)
		button.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		button.add_theme_font_size_override("font_size", 19)
		button.text = "%s\n%s\nStarting Coverage %d" % [
			preset["label"], preset["blurb"], int(preset["coverage"])]
		match key:
			"low":
				button.modulate = Color(0.7, 1.0, 0.78)
			"high":
				button.modulate = Color(1.0, 0.68, 0.6)
			_:
				button.modulate = Color(0.85, 0.9, 1.0)
		button.pressed.connect(_on_deductible_picked.bind(key))
		deductible_rows.add_child(button)


func _on_continue() -> void:
	Sfx.play("ui_confirm")
	_start()


func _on_new_policy() -> void:
	Sfx.play("ui_move")
	menu.visible = false
	deductible_panel.visible = true


func _on_options() -> void:
	Sfx.play("ui_move")
	menu.visible = false
	settings_panel.visible = true


func _on_deductible_picked(key: String) -> void:
	Sfx.play("ui_confirm")
	SaveManager.clear_run()
	GameManager.start_new_run(key)
	_start()


func _start() -> void:
	get_tree().change_scene_to_file(GAME_SCENE)
