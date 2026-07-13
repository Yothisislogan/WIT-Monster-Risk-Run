extends Node
## Versioned local JSON save. Separate sections for profile, run, settings,
## and statistics so future systems can grow independently (GAME_DESIGN.md §24).

const SAVE_PATH := "user://save.json"
const SAVE_VERSION := 1

var data: Dictionary = _default_data()


func _ready() -> void:
	load_data()


static func _default_data() -> Dictionary:
	return {
		"version": SAVE_VERSION,
		"profile": {},   # permanent progression (WIT Headquarters)
		"run": {},       # active run snapshot; empty when no run to resume
		"settings": {},  # control layout, opacity, haptics, accessibility
		"stats": {},     # lifetime statistics
	}


func load_data() -> void:
	if not FileAccess.file_exists(SAVE_PATH):
		data = _default_data()
		return
	var file := FileAccess.open(SAVE_PATH, FileAccess.READ)
	if file == null:
		push_warning("SaveManager: could not open save file, starting fresh.")
		data = _default_data()
		return
	var parsed: Variant = JSON.parse_string(file.get_as_text())
	if typeof(parsed) != TYPE_DICTIONARY:
		push_warning("SaveManager: save file corrupt, starting fresh.")
		data = _default_data()
		return
	data = _migrate(parsed)


func commit() -> void:
	var file := FileAccess.open(SAVE_PATH, FileAccess.WRITE)
	if file == null:
		push_warning("SaveManager: could not write save file.")
		return
	file.store_string(JSON.stringify(data, "\t"))


func get_section(section: String) -> Dictionary:
	return data.get(section, {})


func set_section(section: String, value: Dictionary) -> void:
	data[section] = value
	commit()


func clear_run() -> void:
	set_section("run", {})


func has_resumable_run() -> bool:
	return not get_section("run").is_empty()


## Migrate older saves forward one version at a time. Add a step here for
## every SAVE_VERSION bump so no released version is stranded.
func _migrate(loaded: Dictionary) -> Dictionary:
	var version := int(loaded.get("version", 0))
	if version > SAVE_VERSION:
		push_warning("SaveManager: save from a newer build; using defaults.")
		return _default_data()
	# Fill in any missing sections without discarding player data.
	var merged := _default_data()
	for key in merged.keys():
		if loaded.has(key):
			merged[key] = loaded[key]
	merged["version"] = SAVE_VERSION
	return merged
