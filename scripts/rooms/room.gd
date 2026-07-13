class_name Room
extends Node2D
## Base for handcrafted room modules (GAME_DESIGN.md §12): each room owns a
## SpawnPoint and an Exit area. Sequencing, saving, and transitions are the
## responsibility of GameManager/Main — rooms stay reusable and dumb (§30).

signal exit_reached

@onready var spawn_point: Marker2D = $SpawnPoint

var _exited := false


func _ready() -> void:
	$Exit.body_entered.connect(_on_exit_body_entered)


func _on_exit_body_entered(body: Node2D) -> void:
	if _exited:
		return
	if body is Player:
		_exited = true
		exit_reached.emit()
