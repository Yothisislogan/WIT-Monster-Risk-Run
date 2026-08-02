extends PanelContainer
## WIT HEADQUARTERS (GAME_DESIGN.md §24): the screen between runs.
##
## Not a room you walk around. This is a phone game played in short bursts,
## and a walkable hub would spend a lot of scene work and a lot of the
## player's time on navigation to reach a list of purchases. It is a list of
## purchases. The comedy carries the theming instead.
##
## Two tabs' worth of content in one scroll: what you can buy, and what the
## company has on file about you.

signal closed

@onready var files_label: Label = %HqFiles
@onready var rows: VBoxContainer = %HqRows
@onready var case_rows: VBoxContainer = %HqCaseRows
@onready var close_button: Button = %HqClose


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	close_button.pressed.connect(func() -> void:
		Sfx.play("ui_confirm")
		closed.emit())


func refresh() -> void:
	files_label.text = "CASE FILES ON HAND:  %d" % Headquarters.case_files()
	_build_upgrades()
	_build_case_files()
	_focus_first()


func _focus_first() -> void:
	for row in rows.get_children():
		if row is Button and not (row as Button).disabled:
			(row as Button).call_deferred("grab_focus")
			return
	close_button.call_deferred("grab_focus")


func _build_upgrades() -> void:
	for child in rows.get_children():
		rows.remove_child(child)
		child.queue_free()
	for upgrade in Headquarters.UPGRADES:
		rows.add_child(_build_upgrade_button(upgrade))


func _build_upgrade_button(upgrade: Dictionary) -> Button:
	var id := String(upgrade["id"])
	var current := Headquarters.rank(id)
	var maximum := int(upgrade["ranks"])
	var cost := Headquarters.next_cost(id)
	var button := Button.new()
	button.custom_minimum_size = Vector2(0, 130)
	button.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	button.add_theme_font_size_override("font_size", 23)

	var head := String(upgrade["title"])
	if maximum > 1:
		head += "   [%d/%d]" % [current, maximum]
	elif current > 0:
		head += "   [OWNED]"
	if cost >= 0:
		head += "        %d FILES" % cost
	button.text = "%s\n%s\n%s" % [head, String(upgrade["effect"]), String(upgrade["blurb"])]

	var affordable := Headquarters.can_buy(id)
	button.disabled = not affordable
	if cost < 0:
		button.modulate = Color(0.6, 1.0, 0.7)          # maxed out
	elif affordable:
		button.modulate = Color(1, 1, 1)
	else:
		button.modulate = Color(0.55, 0.55, 0.62)
	button.pressed.connect(_on_buy.bind(id))
	return button


func _on_buy(id: String) -> void:
	if not Headquarters.buy(id):
		return
	Sfx.play("pickup_card")
	refresh()


func _build_case_files() -> void:
	for child in case_rows.get_children():
		case_rows.remove_child(child)
		child.queue_free()
	var earned := CaseFiles.earned()
	for file in CaseFiles.FILES:
		var id := String(file["id"])
		var got := id in earned
		var label := Label.new()
		label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		label.add_theme_font_size_override("font_size", 22)
		# Unearned files still show their name and condition: an achievement
		# you cannot read is not a goal, it is a surprise.
		label.text = "%s  %s — %s" % [
			"[FILED]" if got else "[  OPEN  ]", String(file["title"]), String(file["blurb"])]
		label.modulate = Color(0.75, 1.0, 0.8) if got else Color(1, 1, 1, 0.5)
		case_rows.add_child(label)
