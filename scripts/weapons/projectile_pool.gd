extends Node
## Object pool for projectiles and common effects (GAME_DESIGN.md §30).
## Pooled nodes are parented to the scene tree root-level container so they
## survive the shooter's movement and despawn cleanly.

@export var projectile_scene: PackedScene
@export var initial_size: int = 8

var _available: Array[Node2D] = []


func _ready() -> void:
	for i in initial_size:
		_available.append(_create())


func acquire() -> Node2D:
	var projectile: Node2D = _available.pop_back() if not _available.is_empty() else _create()
	return projectile


func release(projectile: Node2D) -> void:
	_available.append(projectile)


func _create() -> Node2D:
	var projectile: Node2D = projectile_scene.instantiate()
	projectile.pool = self
	projectile.top_level = true  # ignore the shooter's transform once fired
	projectile.visible = false
	projectile.monitoring = false
	projectile.set_physics_process(false)
	add_child(projectile)
	return projectile
