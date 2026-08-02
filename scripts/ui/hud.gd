extends CanvasLayer
## Gameplay HUD (GAME_DESIGN.md §7, §23): large readable Coverage meter,
## charge indicator, currency, pause overlay, and the end-of-run claim
## report (§19). Listens to the Events bus only — no gameplay logic here.

signal restart_requested

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

var _banner_tween: Tween
var _rng := RandomNumberGenerator.new()


func _ready() -> void:
	# Keep working while the tree is paused so the pause overlay is usable.
	process_mode = Node.PROCESS_MODE_ALWAYS
	Events.coverage_changed.connect(_on_coverage_changed)
	Events.player_damaged.connect(_on_player_damaged)
	Events.charge_changed.connect(_on_charge_changed)
	Events.currency_changed.connect(_on_currency_changed)
	Events.shield_changed.connect(_on_shield_changed)
	Events.ability_energy_changed.connect(_on_ability_energy_changed)
	Events.combo_changed.connect(_on_combo_changed)
	_rng.randomize()
	Events.risk_changed.connect(_on_risk_changed)
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
	music_button.pressed.connect(_on_music_pressed)
	_refresh_music_button()


func _on_music_pressed() -> void:
	MusicManager.toggle()
	_refresh_music_button()


func _refresh_music_button() -> void:
	music_button.text = "MUSIC: ON" if MusicManager.enabled else "MUSIC: OFF"


func _process(_delta: float) -> void:
	# The card picker also pauses, so do not stack the two overlays.
	pause_panel.visible = get_tree().paused and not card_panel.visible


func _unhandled_input(event: InputEvent) -> void:
	if card_panel.visible:
		return
	if event.is_action_pressed("pause") and GameManager.run_active:
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
	var ready := current >= GameManager.ABILITY_COST
	ability_label.modulate = Color.WHITE if ready else Color(1, 1, 1, 0.4)


## Room-entry banner: names the Risk Zone, then gets out of the way fast.
func _on_room_started(path: String) -> void:
	var entry := LevelData.entry(path)
	banner_name.text = String(entry.get("name", "UNSURVEYED RISK"))
	banner_sub.text = String(entry.get("subtitle", ""))
	banner_room.text = "ROOM %d / %d" % [
		GameManager.room_index + 1, GameManager.room_sequence.size()]
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
	card_panel.visible = true
	get_tree().paused = true
	Sfx.play("ui_move")


func _build_card_button(card: PolicyCard) -> Button:
	var button := Button.new()
	button.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	button.custom_minimum_size = Vector2(0, 200)
	button.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	button.add_theme_font_size_override("font_size", 17)
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


func _on_run_ended(report: Dictionary) -> void:
	claim_text.text = _format_report(report)
	claim_panel.visible = true


func _format_report(report: Dictionary) -> String:
	var prose := ClaimReport.compose(report, _rng)
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
	])
