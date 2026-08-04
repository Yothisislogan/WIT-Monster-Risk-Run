extends CanvasLayer
## Presents every non-combat Claim Map site (GAME_DESIGN.md §15, §19, §23).
##
## The shop, the rest and the Claim Events are the same screen — a title, some
## prose, and a row of big options — because they are the same decision shape.
## SiteDb owns what the options are and what they do; this owns nothing but
## how they look and the fact that you may only take one.
##
## Options are laid out as wide rows rather than columns: on a phone in
## landscape, three lines of readable prose beats a grid of squares.

@onready var panel: PanelContainer = %SitePanelBody
@onready var title_label: Label = %SiteTitle
@onready var prose_label: Label = %SiteProse
@onready var options_box: VBoxContainer = %SiteOptions
@onready var result_label: Label = %SiteResult
@onready var leave_button: Button = %SiteLeave

var _rng := RandomNumberGenerator.new()
var _resolved: bool = false


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	visible = false
	_rng.randomize()
	leave_button.pressed.connect(_on_leave)
	Events.site_opened.connect(_on_site_opened)


func _on_site_opened(_node_id: int, kind: int) -> void:
	var site := SiteDb.options_for(kind, _rng)
	title_label.text = String(site.get("title", ClaimMap.kind_name(kind)))
	prose_label.text = String(site.get("prose", ""))
	result_label.text = ""
	result_label.visible = false
	_resolved = false
	_build_options(site.get("options", []))
	leave_button.text = "LEAVE"
	visible = true
	get_tree().paused = true
	Sfx.play("ui_move")


func _build_options(options: Array) -> void:
	for child in options_box.get_children():
		options_box.remove_child(child)
		child.queue_free()
	var first: Button = null
	for option in options:
		var button := _build_option_button(option)
		options_box.add_child(button)
		if first == null and not button.disabled:
			first = button
	if first != null:
		first.call_deferred("grab_focus")
	else:
		leave_button.call_deferred("grab_focus")


func _build_option_button(option: Dictionary) -> Button:
	var button := WrappedButton.make(24)
	button.custom_minimum_size = Vector2(0, 112)
	var cost := int(option.get("cost", 0))
	var affordable := SiteDb.affordable(option)
	var head := String(option.get("label", "OPTION"))
	if cost > 0:
		head += "        %d PREMIUMS" % cost
	WrappedButton.caption(button, "%s\n%s" % [head, String(option.get("detail", ""))])
	button.disabled = not affordable
	# Cost is stated on the button and greying is doubled by the disabled
	# state, so affordability never depends on reading a colour (§7).
	WrappedButton.tint(button,
		Color(1, 1, 1) if affordable else Color(0.62, 0.65, 0.72))
	button.pressed.connect(_on_option_pressed.bind(option))
	return button


func _on_option_pressed(option: Dictionary) -> void:
	if _resolved:
		return
	_resolved = true
	Sfx.play("ui_confirm")
	result_label.text = SiteDb.apply(option)
	result_label.visible = true
	# One decision per site. The options stay on screen so you can see what you
	# turned down, but they stop being live.
	for child in options_box.get_children():
		if child is Button:
			(child as Button).disabled = true
	leave_button.text = "CONTINUE"
	leave_button.call_deferred("grab_focus")


func _on_leave() -> void:
	Sfx.play("ui_confirm")
	visible = false
	get_tree().paused = false
	Events.site_resolved.emit()
