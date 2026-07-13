extends "res://scripts/weapons/projectile.gd"
## Flame Draft (GAME_DESIGN.md §12): the Inferno Adjuster's absorbed
## ability. A piercing fire blast that ignites enemies it passes through.

@export var burn_damage_per_tick: int = 5
@export var burn_tick_count: int = 4


func _on_body_entered(body: Node2D) -> void:
	if body.has_method("apply_burn"):
		body.apply_burn(burn_damage_per_tick, burn_tick_count)
	super._on_body_entered(body)
