extends CanvasLayer
## Gameplay HUD (GAME_DESIGN.md §7, §23): large readable Coverage meter,
## charge indicator, currency, pause overlay, and the end-of-run claim
## report (§19). Listens to the Events bus only — no gameplay logic here.

signal restart_requested

@onready var coverage_bar: ProgressBar = %CoverageBar
@onready var coverage_label: Label = %CoverageLabel
@onready var charge_bar: ProgressBar = %ChargeBar
@onready var shield_label: Label = %ShieldLabel
@onready var currency_label: Label = %CurrencyLabel
@onready var claim_panel: PanelContainer = %ClaimPanel
@onready var claim_text: Label = %ClaimText
@onready var restart_button: Button = %RestartButton
@onready var pause_panel: PanelContainer = %PausePanel
@onready var resume_button: Button = %ResumeButton


func _ready() -> void:
	# Keep working while the tree is paused so the pause overlay is usable.
	process_mode = Node.PROCESS_MODE_ALWAYS
	Events.coverage_changed.connect(_on_coverage_changed)
	Events.player_damaged.connect(_on_player_damaged)
	Events.charge_changed.connect(_on_charge_changed)
	Events.currency_changed.connect(_on_currency_changed)
	Events.shield_changed.connect(_on_shield_changed)
	Events.run_started.connect(_on_run_started)
	Events.run_ended.connect(_on_run_ended)
	restart_button.pressed.connect(func() -> void:
		claim_panel.visible = false
		restart_requested.emit())
	resume_button.pressed.connect(func() -> void: get_tree().paused = false)


func _process(_delta: float) -> void:
	pause_panel.visible = get_tree().paused


func _unhandled_input(event: InputEvent) -> void:
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


func _on_run_started() -> void:
	claim_panel.visible = false


func _on_run_ended(report: Dictionary) -> void:
	claim_text.text = _format_report(report)
	claim_panel.visible = true


func _format_report(report: Dictionary) -> String:
	return "\n".join([
		"Cause of loss: %s" % report.get("cause_of_loss", "unknown peril"),
		"Rooms completed: %d" % report.get("rooms_completed", 0),
		"Enemies defeated: %d" % report.get("enemies_defeated", 0),
		"Damage taken: %d" % report.get("damage_taken", 0),
		"Estimated property damage: $%s" % _with_commas(report.get("estimated_property_damage", 0)),
		"",
		"Claim status: %s" % report.get("claim_status", "Under review."),
	])


func _with_commas(value: int) -> String:
	var text := str(value)
	var result := ""
	var count := 0
	for i in range(text.length() - 1, -1, -1):
		result = text[i] + result
		count += 1
		if count % 3 == 0 and i > 0:
			result = "," + result
	return result
