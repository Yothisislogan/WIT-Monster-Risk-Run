extends Node
## Central settings store. Everything the player can change lives here, is
## persisted through SaveManager, and is pushed to whichever system owns it
## (GAME_DESIGN.md §22, §24). Systems never read the save file directly.

signal changed(key: String, value: Variant)

const DEFAULTS := {
	"music_volume": 0.7,
	"music_enabled": true,
	"sfx_volume": 0.8,
	"sfx_enabled": true,
	"control_scale": 1.0,
	"control_opacity": 1.0,
	"left_handed": false,
	"reduced_shake": false,
	"reduced_flashing": false,
	"auto_fire": false,
	"game_speed": 1.0,
}


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS


func get_value(key: String, fallback: Variant = null) -> Variant:
	var settings: Dictionary = SaveManager.get_section("settings")
	if settings.has(key):
		return settings[key]
	if fallback != null:
		return fallback
	return DEFAULTS.get(key, null)


func set_value(key: String, value: Variant) -> void:
	var settings: Dictionary = SaveManager.get_section("settings")
	settings[key] = value
	SaveManager.set_section("settings", settings)
	_apply(key, value)
	changed.emit(key, value)


## Push every stored setting into the system that owns it. Called once at
## startup so a fresh launch matches what the player last chose.
func apply_all() -> void:
	for key in DEFAULTS.keys():
		_apply(String(key), get_value(String(key)))


func _apply(key: String, value: Variant) -> void:
	match key:
		"music_volume":
			MusicManager.volume = clampf(float(value), 0.0, 1.0)
			MusicManager._apply_volume()
		"music_enabled":
			MusicManager.enabled = bool(value)
			MusicManager._apply_volume()
		"sfx_volume":
			Sfx.volume = clampf(float(value), 0.0, 1.0)
		"sfx_enabled":
			Sfx.enabled = bool(value)
		"reduced_shake":
			Juice.reduced_shake = bool(value)
		"reduced_flashing":
			Juice.reduced_flashing = bool(value)
		"game_speed":
			# Juice owns time_scale because hit-stop also drives it.
			Juice.set_base_time_scale(clampf(float(value), 0.4, 1.0))
