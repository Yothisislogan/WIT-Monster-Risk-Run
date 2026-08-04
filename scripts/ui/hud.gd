extends CanvasLayer
## Gameplay HUD (GAME_DESIGN.md §7, §23): large readable Coverage meter,
## charge indicator, currency, pause overlay, and the end-of-run claim
## report (§19). Listens to the Events bus only — no gameplay logic here.

signal restart_requested

const PATCH_COST := 40
const PATCH_HEAL := 45
## Losses fade through dried blood rather than black, so a death reads
## differently from a room transition even before the report appears.
const DEFEAT_FADE := Color(0.22, 0.02, 0.05, 0.0)
const ROOM_FADE := Color(0.0, 0.0, 0.0, 1.0)

@onready var coverage_bar: ProgressBar = %CoverageBar
@onready var coverage_label: Label = %CoverageLabel
@onready var charge_bar: ProgressBar = %ChargeBar
@onready var shield_label: Label = %ShieldLabel
@onready var ability_bar: ProgressBar = %AbilityBar
@onready var ability_label: Label = %AbilityLabel
@onready var currency_label: Label = %CurrencyLabel
@onready var combo_label: Label = %ComboLabel
@onready var claim_panel: PanelContainer = %ClaimPanel
@onready var claim_text: Label = %ClaimText
@onready var restart_button: Button = %RestartButton
@onready var pause_panel: PanelContainer = %PausePanel
@onready var resume_button: Button = %ResumeButton
@onready var music_button: Button = %MusicButton
@onready var banner: VBoxContainer = %Banner
@onready var banner_name: Label = %BannerName
@onready var banner_sub: Label = %BannerSub
@onready var banner_room: Label = %BannerRoom

@onready var risk_bar: ProgressBar = %RiskBar
@onready var risk_label: Label = %RiskLabel
@onready var card_panel: PanelContainer = %CardPanel
@onready var card_row: HBoxContainer = %CardRow
@onready var boss_box: VBoxContainer = %BossBox
@onready var boss_name: Label = %BossName
@onready var boss_bar: ProgressBar = %BossBar
@onready var hint_label: Label = %HintLabel
@onready var inventory_label: Label = %InventoryLabel
@onready var quit_button: Button = %QuitButton
@onready var fade: ColorRect = %Fade

var _banner_tween: Tween
var _rng := RandomNumberGenerator.new()
var _arrow_pool: Array[Polygon2D] = []
var _pause_held: bool = false


func _ready() -> void:
	# Keep working while the tree is paused so the pause overlay is usable.
	process_mode = Node.PROCESS_MODE_ALWAYS
	Events.coverage_changed.connect(_on_coverage_changed)
	Events.player_damaged.connect(_on_player_damaged)
	Events.charge_changed.connect(_on_charge_changed)
	Events.currency_changed.connect(_on_currency_changed)
	Events.shield_changed.connect(_on_shield_changed)
	Events.ability_energy_changed.connect(_on_ability_energy_changed)
	Events.ability_changed.connect(_on_ability_changed)
	Events.ability_granted.connect(_on_ability_granted)
	Events.combo_changed.connect(_on_combo_changed)
	_rng.randomize()
	_build_danger_arrows()
	Events.risk_changed.connect(_on_risk_changed)
	Events.boss_spawned.connect(_on_boss_spawned)
	Events.boss_health_changed.connect(_on_boss_health_changed)
	Events.cards_offered.connect(_on_cards_offered)
	Events.room_started.connect(_on_room_started)
	Events.run_started.connect(_on_run_started)
	Events.run_ended.connect(_on_run_ended)
	restart_button.pressed.connect(func() -> void:
		Sfx.play("ui_confirm")
		claim_panel.visible = false
		restart_requested.emit())
	resume_button.pressed.connect(func() -> void:
		Sfx.play("ui_confirm")
		get_tree().paused = false)
	quit_button.pressed.connect(_on_quit_pressed)
	Events.enemy_weakened.connect(func() -> void:
		_hint("munch", "Green perils are weakened — MUNCH to eat one and heal"))
	music_button.pressed.connect(_on_music_pressed)
	_refresh_music_button()
	# With the touch buttons gone, the ability readout is where you swap
	# abilities: tap the thing that tells you what is equipped. It only becomes
	# interactive once there is a second ability to swap to.
	ability_label.gui_input.connect(_on_ability_label_input)
	ability_label.mouse_filter = Control.MOUSE_FILTER_STOP


func _on_ability_label_input(event: InputEvent) -> void:
	if GameManager.abilities.size() < 2:
		return
	var tapped := event is InputEventScreenTouch and (event as InputEventScreenTouch).pressed
	if tapped or event.is_action_pressed("ui_accept"):
		GameManager.cycle_ability()


func _on_music_pressed() -> void:
	MusicManager.toggle()
	_refresh_music_button()


func _refresh_music_button() -> void:
	music_button.text = "MUSIC: ON" if MusicManager.enabled else "MUSIC: OFF"


func _process(_delta: float) -> void:
	_poll_pause()
	# The card picker also pauses, so do not stack the two overlays.
	_update_danger_arrows()
	var show_pause := get_tree().paused and not _modal_open()
	if show_pause and not pause_panel.visible:
		_refresh_inventory()
		_focus_control(resume_button)
	pause_panel.visible = show_pause


func _on_quit_pressed() -> void:
	Sfx.play("ui_confirm")
	# The run is already checkpointed per room, so quitting is non-destructive.
	# Clearing run_active is not optional: it is what stops GameManager
	# auto-pausing the title screen the next time the app loses focus.
	GameManager.leave_run()
	get_tree().paused = false
	get_tree().change_scene_to_file("res://scenes/title.tscn")


## Pause doubles as the inventory screen (§23): what you are actually holding.
func _refresh_inventory() -> void:
	var lines: Array[String] = []
	for id in GameManager.abilities:
		var ability := Abilities.entry(String(id))
		var equipped := " (equipped)" if String(id) == GameManager.current_ability() else ""
		lines.append("◆ %s%s" % [String(ability.get("name", "")), equipped])
	var combo := GameManager.active_combo()
	if not combo.is_empty():
		lines.append("◆ %s — %s" % [
			String(combo.get("name", "")), String(combo.get("blurb", ""))])
	var entries := GameManager.card_list()
	if entries.is_empty():
		lines.append("")
		lines.append("No endorsements held.")
		inventory_label.text = "\n".join(lines)
		return
	lines.append("")
	for entry in entries:
		var card: PolicyCard = entry["card"]
		var stacks := int(entry["stacks"])
		var suffix := " x%d" % stacks if stacks > 1 else ""
		lines.append("• %s%s" % [card.title, suffix])
	inventory_label.text = "\n".join(lines)


## --- Controller focus (§6 parity) ------------------------------------------
## Every overlay that pauses the game has to hand a gamepad somewhere to
## start, or the pad simply does nothing while the overlay is up. Focus is
## grabbed a frame late because the buttons are built in the same call.

func _focus_control(control: Control) -> void:
	if control == null:
		return
	control.call_deferred("grab_focus")


func _focus_first(container: Node) -> void:
	for child in container.get_children():
		if child is Control and (child as Control).focus_mode != Control.FOCUS_NONE \
				and not (child as Control).is_class("Label"):
			if child is BaseButton and (child as BaseButton).disabled:
				continue
			_focus_control(child)
			return


## One-time contextual teaching, so no tutorial level is needed (§32).
func _hint(id: String, text: String) -> void:
	var profile: Dictionary = SaveManager.get_section("profile")
	var seen: Array = profile.get("hints_seen", [])
	if id in seen:
		return
	seen.append(id)
	profile["hints_seen"] = seen
	SaveManager.set_section("profile", profile)
	hint_label.text = text
	var tween := create_tween()
	tween.tween_property(hint_label, "modulate:a", 1.0, 0.3)
	tween.tween_interval(3.4)
	tween.tween_property(hint_label, "modulate:a", 0.0, 0.6)


## Any overlay that pauses the tree on purpose. The pause panel keys off
## get_tree().paused, so without this it draws on top of the Claim Map and the
## site panel — both of which pause for their own reasons. Membership is a
## group rather than a list of references so a new overlay opts in by joining
## it, instead of by remembering to edit this file.
func _modal_open() -> bool:
	if card_panel.visible:
		return true
	for node in get_tree().get_nodes_in_group("modal_overlay"):
		if node is CanvasLayer and (node as CanvasLayer).visible:
			return true
	return false


## Pause is polled with our own edge detector rather than handled as an event,
## because virtual buttons drive input through Input.action_press(), which
## sets the action state without ever synthesising an InputEvent — so an
## event-based handler is invisible to the on-screen pause button.
func _poll_pause() -> void:
	var held := Input.is_action_pressed("pause")
	var just_pressed := held and not _pause_held
	_pause_held = held
	if not just_pressed or card_panel.visible or not GameManager.run_active:
		return
	get_tree().paused = not get_tree().paused


func _on_coverage_changed(current: int, maximum: int) -> void:
	coverage_bar.max_value = maximum
	coverage_bar.value = current
	# Colorblind-safe: the number always accompanies the bar (§7).
	coverage_label.text = "COVERAGE  %d / %d" % [current, maximum]


func _on_player_damaged(_amount: int, _source: String) -> void:
	coverage_label.modulate = Color(1.0, 0.3, 0.3)
	var tween := create_tween()
	tween.tween_property(coverage_label, "modulate", Color.WHITE, 0.4)


func _on_charge_changed(ratio: float) -> void:
	charge_bar.visible = ratio > 0.0
	charge_bar.value = ratio


func _on_currency_changed(amount: int) -> void:
	currency_label.text = "$ %d" % amount


func _on_shield_changed(active: bool) -> void:
	shield_label.visible = active


## Adjuster's Streak: only appears once it matters, and fades as it expires
## so the player feels the clock without a second bar cluttering the screen.
func _on_combo_changed(count: int, ratio: float) -> void:
	combo_label.visible = count >= 2
	if not combo_label.visible:
		return
	combo_label.text = "STREAK x%d  (%dx PREMIUMS)" % [count, GameManager.combo_multiplier()]
	combo_label.modulate.a = clampf(0.35 + ratio * 0.65, 0.0, 1.0)
	if ratio >= 1.0:
		combo_label.scale = Vector2(1.25, 1.25)
		var tween := create_tween()
		tween.tween_property(combo_label, "scale", Vector2.ONE, 0.18)


func _on_ability_energy_changed(current: float, maximum: float) -> void:
	ability_bar.max_value = maximum
	ability_bar.value = current
	# Bright label = ready to fire; dim = still charging (colorblind-safe
	# because the bar length carries the same information).
	# Not-ready is a cooler, dimmer colour rather than 40% alpha: at 40% the
	# readout vanished into whatever was scrolling behind it, which is the
	# opposite of what a readout is for.
	var ready := current >= GameManager.ability_cost()
	ability_label.modulate = Color.WHITE if ready else Color(0.58, 0.63, 0.74, 1)


## The label names the equipped ability rather than assuming Flame Draft, and
## says so when a combination is changing how it behaves (§14).
func _on_ability_changed(ability_id: String) -> void:
	var entry := Abilities.entry(ability_id)
	var text := String(entry.get("name", "ABILITY"))
	if GameManager.abilities.size() > 1:
		text += "  (%d/%d)" % [GameManager.ability_index + 1, GameManager.abilities.size()]
	var combo := GameManager.active_combo()
	if not combo.is_empty():
		text += "  ·  %s" % String(combo.get("name", ""))
	ability_label.text = text


func _on_ability_granted(ability_id: String) -> void:
	var entry := Abilities.entry(ability_id)
	var combo := GameManager.active_combo()
	var lines := ["ABILITY ABSORBED — %s" % String(entry.get("name", "")),
			String(entry.get("blurb", ""))]
	if not combo.is_empty():
		lines.append("%s unlocked: %s" % [
			String(combo.get("name", "")), String(combo.get("blurb", ""))])
	if GameManager.abilities.size() > 1:
		lines.append("Kept for good — every future run starts with both. Press CYCLE to swap.")
	# Not a one-time hint: absorbing a power is rare enough to always announce.
	hint_label.text = "\n".join(lines)
	hint_label.modulate.a = 0.0
	var tween := create_tween()
	tween.tween_property(hint_label, "modulate:a", 1.0, 0.3)
	tween.tween_interval(4.2)
	tween.tween_property(hint_label, "modulate:a", 0.0, 0.6)
	Sfx.play("pickup_card")


## Room-entry banner: names the Risk Zone, then gets out of the way fast.
func _on_room_started(path: String) -> void:
	# Fade up from black so a room swap reads as a cut, not a pop. The whole
	# colour is reset, not just alpha — a previous defeat left it red.
	fade.color = ROOM_FADE
	var fade_tween := create_tween()
	fade_tween.tween_property(fade, "color:a", 0.0, 0.35)
	boss_box.visible = false
	var entry := LevelData.entry(path)
	banner_name.text = String(entry.get("name", "UNSURVEYED RISK"))
	banner_sub.text = String(entry.get("subtitle", ""))
	var progress := GameManager.route_progress()
	banner_room.text = "SITE %d / %d" % [progress.x, progress.y]
	if DisplayServer.is_touchscreen_available():
		_hint("gestures", "TAP to jump  ·  SWIPE ← → to dash  ·  SWIPE ↑ for your ability\n"
				+ "SWIPE ↓ to pound in the air, or eat a weakened peril on the ground\n"
				+ "HOLD to charge a shot  ·  TWO FINGERS to pause")
	else:
		_hint("double_jump", "Tap JUMP again in mid-air to double jump")
	if _banner_tween != null and _banner_tween.is_valid():
		_banner_tween.kill()
	banner.modulate.a = 0.0
	banner.position.y = 12.0
	_banner_tween = create_tween()
	_banner_tween.set_parallel(true)
	_banner_tween.tween_property(banner, "modulate:a", 1.0, 0.28)
	_banner_tween.tween_property(banner, "position:y", 0.0, 0.35)
	_banner_tween.set_parallel(false)
	_banner_tween.tween_interval(1.5)
	_banner_tween.tween_property(banner, "modulate:a", 0.0, 0.5)


func _on_boss_spawned(title: String, maximum: int) -> void:
	_hint("boss", "Every attack telegraphs. Punish the stun that follows.")
	boss_name.text = title
	boss_bar.max_value = maximum
	boss_bar.value = maximum
	boss_box.visible = true
	boss_box.modulate.a = 0.0
	var tween := create_tween()
	tween.tween_property(boss_box, "modulate:a", 1.0, 0.5)


func _on_boss_health_changed(current: int, maximum: int) -> void:
	boss_bar.max_value = maximum
	boss_bar.value = current
	if current <= 0:
		var tween := create_tween()
		tween.tween_property(boss_box, "modulate:a", 0.0, 0.8)
		tween.tween_callback(func() -> void: boss_box.visible = false)


func _on_risk_changed(value: float) -> void:
	risk_bar.value = value
	risk_label.text = "RISK: %s" % ClaimReport.risk_label(value)
	risk_label.modulate = Color(1, 1, 1) if value < 0.5 else Color(1, 0.6, 0.6)


## Card offer between rooms (§9). Pauses so the choice is unhurried, and the
## three options are big touch targets rather than a scrolling list (§9, §23).
func _on_cards_offered(cards: Array) -> void:
	for child in card_row.get_children():
		child.queue_free()
	if cards.is_empty():
		Events.card_chosen.emit("")
		return
	for card in cards:
		card_row.add_child(_build_card_button(card))
	var repair := _build_patch_button()
	if repair != null:
		card_row.add_child(repair)
	card_panel.visible = true
	get_tree().paused = true
	Sfx.play("ui_move")
	# Without this the run's central decision is mouse/touch only: a gamepad
	# has nothing focused to move away from (§6 controller parity).
	_focus_first(card_row)


## Spend Premiums instead of taking an endorsement (§15 shop, compressed into
## the same decision so it is one screen rather than two).
func _build_patch_button() -> Button:
	if GameManager.coverage >= GameManager.max_coverage:
		return null
	var cost := PATCH_COST
	var button := Button.new()
	button.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	button.custom_minimum_size = Vector2(0, 480)
	button.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	button.add_theme_font_size_override("font_size", 22)
	var affordable := GameManager.currency >= cost
	button.text = "\n".join([
		"PATCH UP", "",
		"Restore %d Coverage instead of taking an endorsement." % PATCH_HEAL,
		"", "COST: %d PREMIUMS" % cost])
	button.disabled = not affordable
	button.modulate = Color(0.6, 1.0, 0.7) if affordable else Color(0.5, 0.5, 0.5)
	button.pressed.connect(_on_patch_picked)
	return button


func _on_patch_picked() -> void:
	if not GameManager.spend_currency(PATCH_COST):
		return
	GameManager.heal(PATCH_HEAL)
	Sfx.play("pickup_card")
	card_panel.visible = false
	get_tree().paused = false
	Events.card_chosen.emit("")


func _build_card_button(card: PolicyCard) -> Button:
	var button := Button.new()
	button.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	button.custom_minimum_size = Vector2(0, 480)
	button.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	button.add_theme_font_size_override("font_size", 22)
	var lines := [card.title.to_upper(), "", card.text]
	if card.is_exclusion:
		lines.append("")
		lines.append("EXCLUSION — " + card.downside)
	lines.append("")
	lines.append("%s · %s" % [card.category.to_upper(), card.rarity_name()])
	button.text = "\n".join(lines)
	button.modulate = Color(1.0, 0.72, 0.55) if card.is_exclusion else card.rarity_color()
	button.pressed.connect(_on_card_picked.bind(card.id))
	return button


func _on_card_picked(card_id: String) -> void:
	Sfx.play("pickup_card")
	card_panel.visible = false
	get_tree().paused = false
	Events.card_chosen.emit(card_id)


func _on_run_started() -> void:
	card_panel.visible = false
	claim_panel.visible = false
	boss_box.visible = false
	hint_label.modulate.a = 0.0


func _on_run_ended(report: Dictionary) -> void:
	claim_text.text = _format_report(report)
	if bool(report.get("victory", false)):
		_show_claim_panel()
		return
	# A loss gets a beat. The Monster is still falling out of frame at this
	# point (player.gd drives that), so the report waits behind a fade
	# instead of landing on top of the moment it is reporting on.
	var tween := create_tween()
	tween.set_ignore_time_scale(true)  # Juice.hit_stop has time_scale at 0
	fade.color = DEFEAT_FADE
	tween.tween_interval(0.45)
	tween.tween_property(fade, "color:a", 0.9, 0.55)
	tween.tween_interval(0.2)
	tween.tween_callback(_show_claim_panel)
	tween.tween_property(fade, "color:a", 0.0, 0.45)


func _show_claim_panel() -> void:
	claim_panel.visible = true
	_focus_control(restart_button)


func _format_report(report: Dictionary) -> String:
	var prose := ClaimReport.compose(report, _rng)
	# What the run bought you permanently goes last, so the eye lands on it —
	# it is the reason to press RESTART rather than close the app (§24).
	var tail: Array[String] = ["", "CASE FILES FILED:  %d  (%d on hand)" % [
		int(report.get("case_files_awarded", 0)), Headquarters.case_files()]]
	for file in report.get("case_files_new", []):
		tail.append("   NEW CASE FILE — %s" % String(file.get("title", "")))
	return "\n".join([
		"Cause of loss:  %s" % prose["cause"],
		"Contributing factor:  %s" % prose["factor"],
		"",
		"Policy:  %s" % report.get("deductible", "STANDARD DEDUCTIBLE"),
		"Final risk assessment:  %s" % ClaimReport.risk_label(report.get("risk", 0.0)),
		"Rooms surveyed:  %d          Perils neutralised:  %d" % [
			report.get("rooms_completed", 0), report.get("enemies_defeated", 0)],
		"Parties consumed:  %d          Best streak:  x%d" % [
			report.get("enemies_consumed", 0), report.get("best_combo", 0)],
		"Endorsements held:  %d          Premiums collected:  %d" % [
			report.get("cards", 0), report.get("premiums_earned", 0)],
		"Estimated property damage:  $%s" % ClaimReport.money(
			report.get("estimated_property_damage", 0)),
		"",
		"CLAIM STATUS:  %s" % prose["status"],
	] + tail)


## --- Off-screen danger indicators (§17) ------------------------------------
## Arrows at the screen edge for perils you cannot see yet. Without these,
## an Ember Imp diving from off-camera reads as an unfair hit.
func _update_danger_arrows() -> void:
	if _arrow_pool.is_empty():
		return
	var camera := get_viewport().get_camera_2d()
	if camera == null or not GameManager.run_active:
		for arrow in _arrow_pool:
			arrow.visible = false
		return
	var centre := camera.get_screen_center_position()
	# CanvasLayer is a Node, not a CanvasItem, so it has no get_viewport_rect().
	var size := get_viewport().get_visible_rect().size
	var margin := 46.0
	var index := 0
	for enemy in get_tree().get_nodes_in_group("enemies"):
		if index >= _arrow_pool.size():
			break
		if not is_instance_valid(enemy):
			continue
		var offset: Vector2 = enemy.global_position - centre
		# Only flag things that are genuinely off screen but still close by.
		if absf(offset.x) < size.x * 0.5 and absf(offset.y) < size.y * 0.5:
			continue
		if offset.length() > 900.0:
			continue
		var arrow: Polygon2D = _arrow_pool[index]
		index += 1
		var edge := Vector2(
			clampf(offset.x, -size.x * 0.5 + margin, size.x * 0.5 - margin),
			clampf(offset.y, -size.y * 0.5 + margin, size.y * 0.5 - margin))
		arrow.position = size * 0.5 + edge
		arrow.rotation = offset.angle()
		arrow.visible = true
	for i in range(index, _arrow_pool.size()):
		_arrow_pool[i].visible = false


func _build_danger_arrows() -> void:
	for i in 6:
		var arrow := Polygon2D.new()
		arrow.polygon = PackedVector2Array([
			Vector2(14, 0), Vector2(-8, -9), Vector2(-3, 0), Vector2(-8, 9)])
		arrow.color = Color(1.0, 0.4, 0.35, 0.85)
		arrow.visible = false
		$Root.add_child(arrow)
		_arrow_pool.append(arrow)
