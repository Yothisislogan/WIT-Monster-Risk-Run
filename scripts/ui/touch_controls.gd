extends CanvasLayer
## Touch control layer. Visible only on touch devices; desktop and
## controller players never see it. Opacity comes from saved settings so
## players can tune it later (GAME_DESIGN.md §6, §22).

@onready var root: Control = $Root


func _ready() -> void:
	visible = DisplayServer.is_touchscreen_available()
	var settings: Dictionary = SaveManager.get_section("settings")
	root.modulate.a = float(settings.get("control_opacity", 1.0))
