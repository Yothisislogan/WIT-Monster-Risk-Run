extends Area2D
## Temporary upgrade pickup for the prototype: Umbrella Coverage (§9) —
## blocks one hit. Stands in for the full Policy Card system (Phase 3).

func _on_body_entered(body: Node2D) -> void:
	if body is Player:
		GameManager.grant_umbrella()
		Sfx.play("pickup_card")
		queue_free()
