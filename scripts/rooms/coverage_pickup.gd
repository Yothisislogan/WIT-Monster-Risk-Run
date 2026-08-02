extends Area2D
## "First Aid Rider" — restores Coverage. Deliberately scarce: healing is the
## resource the Risk Meter and the High Deductible both squeeze (§8, §11).

@export var heal_amount: int = 22
@export var bob_speed: float = 3.4

@onready var visual: Node2D = $Visual

var _age: float = 0.0


func _physics_process(delta: float) -> void:
	_age += delta
	visual.position.y = sin(_age * bob_speed) * 4.0
	visual.scale = Vector2.ONE * (1.0 + sin(_age * bob_speed * 0.5) * 0.06)


func _on_body_entered(body: Node2D) -> void:
	if not body is Player:
		return
	# Never waste one: at full Coverage it stays on the ground for later.
	if GameManager.coverage >= GameManager.max_coverage:
		return
	GameManager.heal(heal_amount)
	Sfx.play("pickup_card", 0.05)
	Juice.burst(global_position, 12, Color(0.45, 1.0, 0.55), 220.0)
	queue_free()
