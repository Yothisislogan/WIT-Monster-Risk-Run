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
			"backdrop": Color(0.42, 0.20, 0.16),
	},
	"test_room_b": {
		"name": "CRASHWAY 5000",
		"subtitle": "Highway — do not stop for photos",
		"music": "crashway_5000",
			"backdrop": Color(0.20, 0.24, 0.40),
	},
	"test_room_c": {
		"name": "STORM SURGE HARBOR",
		"subtitle": "Flood zone — coverage excluded",
		"music": "storm_surge_harbor",
			"backdrop": Color(0.14, 0.32, 0.36),
	},
	"test_room_d": {
		"name": "CYBER CITY",
		"subtitle": "Data breach in progress",
		"music": "cyber_city",
			"backdrop": Color(0.16, 0.20, 0.46),
	},
	"test_room_e": {
		"name": "LIABILITY LAND",
		"subtitle": "Park closed — see attendant",
		"music": "liability_land",
			"backdrop": Color(0.38, 0.18, 0.36),
	},
	"boss_actuary": {
		"name": "THE ACTUARY",
		"subtitle": "It has run the numbers",
		"music": "boss_theme",
			"backdrop": Color(0.14, 0.18, 0.38),
	},
	"boss_inferno_adjuster": {
		"name": "THE INFERNO ADJUSTER",
		"subtitle": "Your claim is being denied",
		"music": "boss_theme",
			"backdrop": Color(0.46, 0.14, 0.12),
	},
}

## Room scenes a combat node can draw. Kept here rather than in GameManager so
## that "what rooms exist" and "what each room is called" are one fact in one
## file (§29 data-driven resources).
const COMBAT_ROOMS: Array[String] = [
	"res://scenes/rooms/test_room_a.tscn",
	"res://scenes/rooms/test_room_b.tscn",
	"res://scenes/rooms/test_room_c.tscn",
	"res://scenes/rooms/test_room_d.tscn",
	"res://scenes/rooms/test_room_e.tscn",
]

## Bosses in act order, cycled. With three acts and two bosses a run does see
## one of them twice — but cycling rather than clamping means never twice in a
## row, and the Risk Meter has moved a long way by the third act. Adding a
## third boss is one line here and the repeat disappears.
const BOSS_ROOMS: Array[String] = [
	"res://scenes/rooms/boss_actuary.tscn",
	"res://scenes/rooms/boss_inferno_adjuster.tscn",
]

const FALLBACK := {
	"name": "UNSURVEYED RISK",
	"subtitle": "No inspection on file",
	"music": "blaze_borough",
	"backdrop": Color(0.2, 0.24, 0.38),
}


static func boss_room_for(act: int) -> String:
	if BOSS_ROOMS.is_empty():
		return ""
	return BOSS_ROOMS[act % BOSS_ROOMS.size()]


static func key_for(scene_path: String) -> String:
	return scene_path.get_file().get_basename()


static func entry(scene_path: String) -> Dictionary:
	return ROOMS.get(key_for(scene_path), FALLBACK)
