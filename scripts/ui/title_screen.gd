extends Control
## Title screen and run setup. A returning player with a saved run sees
## CONTINUE first; a new player sees the deductible choice, which is where
## difficulty is actually selected (GAME_DESIGN.md §8, §23).
##
## The screen is composed inside a "Stage" child sized to exactly 1280x720 and
## anchored to the centre. The project stretches with aspect "expand", so on a
## wider phone the viewport really is wider than the design box; keeping the
## composition in one centred Stage means every position on this screen is a
## plain design coordinate, and the extra width shows as more sky rather than
## as a menu drifting into a corner.
##
## Splash, Monster and Logo are decoration and own no input. Lightning from the
## backdrop is forwarded to the other two here, so neither has to go looking
## through the tree for the other.

const GAME_SCENE := "res://scenes/main.tscn"

## Menu geometry. Four entries is the most the menu ever shows (CONTINUE RUN
## only appears with a save), and tools/check_title.py checks that four of
## these plus the separator still fit the Menu box in scenes/title.tscn.
const MENU_BUTTON_SIZE := Vector2(420.0, 68.0)
const MENU_MAX_ENTRIES := 4
const MENU_FONT_SIZE := 30

@onready var front: Control = %Front
@onready var splash: Node2D = %Splash
@onready var monster: Node2D = %Monster
@onready var logo: Control = %Logo
@onready var menu: VBoxContainer = %Menu
@onready var deductible_panel: PanelContainer = %DeductiblePanel
@onready var deductible_rows: VBoxContainer = %DeductibleRows
@onready var settings_panel: PanelContainer = %SettingsPanel
@onready var headquarters: PanelContainer = %HeadquartersPanel
@onready var record_label: Label = %RecordLabel


func _ready() -> void:
	Settings.apply_all()
	settings_panel.visible = false
	deductible_panel.visible = false
	headquarters.visible = false
	splash.lightning_struck.connect(_on_lightning)
	headquarters.closed.connect(func() -> void:
		headquarters.visible = false
		front.visible = true
		_show_record()
		_build_menu())
	settings_panel.closed.connect(func() -> void:
		settings_panel.visible = false
		front.visible = true
		_build_menu())
	_build_menu()
	_build_deductibles()
	_show_record()
	MusicManager.play("blaze_borough")


## One signal in, two reactions out: the Monster startles and the wordmark
## catches the light. Neither knows the other exists.
func _on_lightning(strength: float) -> void:
	monster.on_lightning(strength)
	logo.on_lightning(strength)


func _show_record() -> void:
	var lifetime: Dictionary = SaveManager.get_section("stats")
	var runs := int(lifetime.get("runs", 0))
	var lines: Array[String] = []
	if runs == 0:
		lines.append("No claims on file.")
	else:
		lines.append("Claims filed: %d     Survived: %d     Worst loss: $%s" % [
			runs, int(lifetime.get("wins", 0)),
			ClaimReport.money(int(lifetime.get("best_property_damage", 0)))])
	# WIT Headquarters (§24): powers taken off bosses are the one thing that
	# survives a run, so the title screen is where you see them accumulate.
	var unlocked := GameManager.unlocked_abilities()
	if unlocked.size() > 1:
		var names: Array[String] = []
		for id in unlocked:
			names.append(String(Abilities.entry(String(id)).get("name", "")))
		lines.append("Powers absorbed: " + "  ·  ".join(names))
		var combo := Abilities.combo_for(unlocked)
		if not combo.is_empty():
			lines.append("%s active — %s" % [
				String(combo.get("name", "")), String(combo.get("blurb", ""))])
	record_label.text = "\n".join(lines)


func _build_menu() -> void:
	for child in menu.get_children():
		menu.remove_child(child)
		child.queue_free()
	var first: Button = null
	if SaveManager.has_resumable_run():
		first = _button("CONTINUE RUN", _on_continue)
		menu.add_child(first)
	var new_policy := _button("NEW POLICY", _on_new_policy)
	menu.add_child(new_policy)
	menu.add_child(_button("WIT HEADQUARTERS", _on_headquarters))
	menu.add_child(_button("OPTIONS", _on_options))
	# A controller needs something focused or the whole title screen is inert.
	# Focus the button we just made, not menu.get_child(0) — the old buttons
	# are only queue_freed and would still be there to be picked up.
	if first == null:
		first = new_policy
	first.call_deferred("grab_focus")


func _button(text: String, handler: Callable) -> Button:
	var button := Button.new()
	button.text = text
	button.custom_minimum_size = MENU_BUTTON_SIZE
	button.add_theme_font_size_override("font_size", MENU_FONT_SIZE)
	button.pressed.connect(handler)
	return button


func _build_deductibles() -> void:
	# remove_child before queue_free, for the same reason _build_menu does it:
	# queue_free defers to the end of the frame, so a freed child is still in
	# the tree — and _on_new_policy focuses deductible_rows.get_child(1), which
	# would pick a stale button that is about to vanish.
	for child in deductible_rows.get_children():
		deductible_rows.remove_child(child)
		child.queue_free()
	for key in ["low", "standard", "high"]:
		var preset: Dictionary = GameManager.DEDUCTIBLES[key]
		var button := Button.new()
		button.custom_minimum_size = Vector2(0, 146)
		button.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		button.add_theme_font_size_override("font_size", 26)
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


## Every panel hides Front and leaves Splash running, so the storm keeps going
## behind the modal instead of the screen cutting to a flat colour. Front is
## the wordmark, the Monster, the menu and the record line — everything the
## panel would otherwise be competing with for attention.
func _on_new_policy() -> void:
	Sfx.play("ui_move")
	front.visible = false
	deductible_panel.visible = true
	# STANDARD is the middle row and the sane default to land on.
	(deductible_rows.get_child(1) as Button).call_deferred("grab_focus")


func _on_headquarters() -> void:
	Sfx.play("ui_move")
	front.visible = false
	headquarters.visible = true
	headquarters.refresh()


func _on_options() -> void:
	Sfx.play("ui_move")
	front.visible = false
	settings_panel.visible = true
	settings_panel.focus_first()


func _on_deductible_picked(key: String) -> void:
	Sfx.play("ui_confirm")
	SaveManager.clear_run()
	GameManager.start_new_run(key)
	_start()


func _start() -> void:
	get_tree().change_scene_to_file(GAME_SCENE)
