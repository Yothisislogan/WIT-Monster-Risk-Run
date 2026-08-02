extends Room
## Boss arena. The exit stays sealed until the boss is down, so the room can
## only be completed by winning the fight (GAME_DESIGN.md §15 mini-boss/boss).

@onready var boss: Node = $Enemies/Boss
@onready var exit_area: Area2D = $Exit


func _ready() -> void:
	super._ready()
	_set_exit_open(false)
	if is_instance_valid(boss):
		boss.defeated.connect(_on_boss_defeated)
	else:
		# No boss in the scene means nothing to beat; do not trap the player.
		_set_exit_open(true)


func _on_boss_defeated() -> void:
	Events.boss_defeated.emit()
	_set_exit_open(true)


func _set_exit_open(open: bool) -> void:
	exit_area.visible = open
	exit_area.set_deferred("monitoring", open)
