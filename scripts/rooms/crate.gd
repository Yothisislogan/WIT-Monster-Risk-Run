extends StaticBody2D
## "Unattended Property" — a solid crate you can stand on, shoot, dash
## through, or ground-pound. Breaking it showers Premiums (§19 property
## damage is a feature, not a bug).

@export var max_health: int = 20
@export var premium_drops: int = 3
@export var premium_scene: PackedScene
@export var debris_color: Color = Color(0.72, 0.55, 0.35)

@onready var visual: Node2D = $Visual

var health: int


func _ready() -> void:
	health = max_health


func take_damage(amount: int) -> void:
	health -= amount
	visual.modulate = Color(2.5, 2.5, 2.5)
	var tween := create_tween()
	tween.tween_property(visual, "modulate", Color.WHITE, 0.12)
	visual.scale = Vector2(1.15, 0.85)
	tween.parallel().tween_property(visual, "scale", Vector2.ONE, 0.12)
	if health <= 0:
		shatter()


func shatter() -> void:
	Juice.debris(global_position, debris_color)
	Juice.shake(3.0, 0.15)
	_spawn_premiums()
	queue_free()


func _spawn_premiums() -> void:
	if premium_scene == null:
		GameManager.add_currency(premium_drops)
		return
	var parent := get_parent()
	for i in premium_drops:
		var premium: Node2D = premium_scene.instantiate()
		premium.global_position = global_position
		# Fan the drops out so they read as a satisfying little payout.
		var spread := float(i) / maxf(float(premium_drops - 1), 1.0) - 0.5
		premium.pop(Vector2(spread * 220.0, -320.0 - absf(spread) * 60.0))
		parent.add_child(premium)
