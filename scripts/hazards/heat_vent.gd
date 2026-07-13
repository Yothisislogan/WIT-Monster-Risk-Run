extends Area2D
## Heat Vent hazard (Blaze Borough, §12): cycles between a telegraphed
## warm-up and a damaging burst. Telegraphs are mandatory on mobile (§16).

@export var damage: int = 15
@export var idle_time: float = 1.5
@export var warn_time: float = 0.6
@export var active_time: float = 1.0

@onready var flame: Polygon2D = $Flame

var _timer: float = 0.0
var _state: int = 0  # 0 idle, 1 warning, 2 active


func _ready() -> void:
	monitoring = false
	flame.visible = false


func _physics_process(delta: float) -> void:
	_timer += delta
	match _state:
		0:  # idle
			if _timer >= idle_time:
				_enter_state(1)
				flame.visible = true
				flame.modulate = Color(1, 0.8, 0.3, 0.35)
				flame.scale = Vector2(1.0, 0.25)
		1:  # warning: small translucent flicker
			flame.modulate.a = 0.25 + 0.2 * sin(_timer * 30.0)
			if _timer >= warn_time:
				_enter_state(2)
				flame.modulate = Color(1, 0.55, 0.1, 1.0)
				flame.scale = Vector2.ONE
				monitoring = true
		2:  # active: full flame, damaging
			if _timer >= active_time:
				_enter_state(0)
				flame.visible = false
				monitoring = false


func _enter_state(state: int) -> void:
	_state = state
	_timer = 0.0


func _on_body_entered(body: Node2D) -> void:
	if body is Player:
		body.hurt(damage, "roasted by a heat vent")
