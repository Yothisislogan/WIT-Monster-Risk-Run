class_name LevelData
extends RefCounted
## Single source of truth for per-room presentation: display name, subtitle and
## music. Both the HUD banner and MusicManager read from here so a new room is
## registered in exactly one place (GAME_DESIGN.md §29 data-driven resources).

const ROOMS := {
	"test_room_a": {
		"name": "BLAZE BOROUGH",
		"subtitle": "Residential — total loss likely",
		"music": "blaze_borough",
	},
	"test_room_b": {
		"name": "CRASHWAY 5000",
		"subtitle": "Highway — do not stop for photos",
		"music": "crashway_5000",
	},
	"test_room_c": {
		"name": "STORM SURGE HARBOR",
		"subtitle": "Flood zone — coverage excluded",
		"music": "storm_surge_harbor",
	},
	"test_room_d": {
		"name": "CYBER CITY",
		"subtitle": "Data breach in progress",
		"music": "cyber_city",
	},
	"test_room_e": {
		"name": "LIABILITY LAND",
		"subtitle": "Park closed — see attendant",
		"music": "liability_land",
	},
	"boss_inferno_adjuster": {
		"name": "THE INFERNO ADJUSTER",
		"subtitle": "Your claim is being denied",
		"music": "blaze_borough",
	},
}

const FALLBACK := {
	"name": "UNSURVEYED RISK",
	"subtitle": "No inspection on file",
	"music": "blaze_borough",
}


static func key_for(scene_path: String) -> String:
	return scene_path.get_file().get_basename()


static func entry(scene_path: String) -> Dictionary:
	return ROOMS.get(key_for(scene_path), FALLBACK)
