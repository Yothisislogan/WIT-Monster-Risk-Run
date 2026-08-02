extends Node
## Game-feel layer: screen shake, hit-stop, and pooled particle bursts.
## Everything here is presentation only — gameplay never depends on it, and
## every effect respects the accessibility toggles (GAME_DESIGN.md §22).

const POOL_SIZE := 12

var reduced_shake: bool = false
var reduced_flashing: bool = false

var _camera: Camera2D = null
var _shake_amount: float = 0.0
var _shake_decay: float = 0.0
var _shake_offset: Vector2 = Vector2.ZERO
var _hit_stop_active: bool = false
var _base_time_scale: float = 1.0

var _pool: Array[CPUParticles2D] = []
var _pool_index: int = 0
var _numbers: Array[Label] = []
var _number_index: int = 0


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	var settings: Dictionary = SaveManager.get_section("settings")
	reduced_shake = bool(settings.get("reduced_shake", false))
	reduced_flashing = bool(settings.get("reduced_flashing", false))
	for i in POOL_SIZE:
		var particles := CPUParticles2D.new()
		particles.emitting = false
		particles.one_shot = true
		particles.top_level = true
		add_child(particles)
		_pool.append(particles)
	for i in 10:
		var label := Label.new()
		label.top_level = true
		label.visible = false
		label.z_index = 200
		label.add_theme_font_size_override("font_size", 27)
		add_child(label)
		_numbers.append(label)


func _process(delta: float) -> void:
	if _shake_amount <= 0.0:
		return
	_shake_amount = maxf(_shake_amount - _shake_decay * delta, 0.0)
	_shake_offset = Vector2(
		randf_range(-_shake_amount, _shake_amount),
		randf_range(-_shake_amount, _shake_amount)
	)


## Current shake offset; the camera applies it so shake composes with look-ahead.
func shake_offset() -> Vector2:
	return _shake_offset if _shake_amount > 0.0 else Vector2.ZERO


func register_camera(camera: Camera2D) -> void:
	_camera = camera


## amount = pixels of jitter, duration = seconds to decay to zero.
func shake(amount: float, duration: float = 0.25) -> void:
	if reduced_shake:
		return
	_shake_amount = maxf(_shake_amount, amount)
	_shake_decay = _shake_amount / maxf(duration, 0.01)


## Brief freeze on impactful hits. Values are in seconds of real time.
func hit_stop(duration: float) -> void:
	if _hit_stop_active or duration <= 0.0:
		return
	_hit_stop_active = true
	Engine.time_scale = 0.0
	# ignore_time_scale = true so the timer still fires while frozen.
	await get_tree().create_timer(duration, true, false, true).timeout
	Engine.time_scale = _base_time_scale
	_hit_stop_active = false


## The accessibility game-speed option (§22). Hit-stop restores to this
## rather than to 1.0, so the two never fight.
func set_base_time_scale(value: float) -> void:
	_base_time_scale = clampf(value, 0.4, 1.0)
	if not _hit_stop_active:
		Engine.time_scale = _base_time_scale


## Generic one-shot burst. Reuses pooled emitters so combat never allocates.
func burst(position: Vector2, count: int, color: Color, speed: float,
		spread_degrees: float = 180.0, direction: Vector2 = Vector2.UP,
		scale_px: float = 4.0, lifetime: float = 0.45) -> void:
	var particles := _acquire()
	particles.global_position = position
	particles.amount = maxi(count, 1)
	particles.lifetime = lifetime
	particles.direction = direction
	particles.spread = spread_degrees
	particles.initial_velocity_min = speed * 0.4
	particles.initial_velocity_max = speed
	particles.gravity = Vector2(0.0, 900.0)
	particles.scale_amount_min = scale_px
	particles.scale_amount_max = scale_px * 1.6
	particles.color = color
	particles.restart()


func dust(position: Vector2, amount: int = 8) -> void:
	burst(position, amount, Color(0.85, 0.85, 0.9, 0.8), 160.0, 60.0, Vector2.UP, 3.0, 0.35)


func jump_puff(position: Vector2) -> void:
	burst(position, 8, Color(0.9, 0.94, 1.0, 0.85), 190.0, 55.0, Vector2.DOWN, 3.0, 0.3)


func double_jump_ring(position: Vector2) -> void:
	burst(position, 14, Color(0.4, 0.8, 1.0, 0.95), 240.0, 180.0, Vector2.UP, 3.5, 0.35)


func land_dust(position: Vector2, strength: float) -> void:
	var amount := clampi(int(4.0 + strength * 10.0), 4, 18)
	burst(position, amount, Color(0.85, 0.85, 0.9, 0.85), 120.0 + strength * 220.0,
			30.0, Vector2.UP, 3.0, 0.35)


func hit_spark(position: Vector2) -> void:
	burst(position, 10, Color(1.0, 0.9, 0.35), 300.0, 180.0, Vector2.UP, 3.5, 0.28)


func enemy_death(position: Vector2, color: Color = Color(1.0, 0.55, 0.25)) -> void:
	burst(position, 18, color, 340.0, 180.0, Vector2.UP, 4.5, 0.5)


func debris(position: Vector2, color: Color = Color(0.72, 0.55, 0.35)) -> void:
	burst(position, 14, color, 280.0, 180.0, Vector2.UP, 5.0, 0.6)


func coin_sparkle(position: Vector2) -> void:
	burst(position, 6, Color(1.0, 0.85, 0.25), 150.0, 180.0, Vector2.UP, 3.0, 0.3)


func shockwave(position: Vector2) -> void:
	burst(position, 22, Color(1.0, 0.75, 0.3, 0.95), 420.0, 25.0, Vector2.RIGHT, 5.0, 0.4)
	burst(position, 22, Color(1.0, 0.75, 0.3, 0.95), 420.0, 25.0, Vector2.LEFT, 5.0, 0.4)


## Floating damage number. Tells the player their hits are landing and how
## hard — the difference between a hit registering and a hit feeling good.
func damage_number(position: Vector2, amount: int, color: Color = Color(1.0, 0.92, 0.45)) -> void:
	var label := _numbers[_number_index]
	_number_index = (_number_index + 1) % _numbers.size()
	label.text = str(amount)
	label.modulate = color
	label.scale = Vector2.ONE * 1.5
	label.visible = true
	var from := position + Vector2(randf_range(-14.0, 14.0), -26.0)
	label.global_position = from
	var tween := create_tween()
	tween.set_parallel(true)
	tween.tween_property(label, "global_position", from + Vector2(0.0, -52.0), 0.65)
	tween.tween_property(label, "scale", Vector2.ONE, 0.14)
	tween.tween_property(label, "modulate:a", 0.0, 0.65).set_delay(0.15)
	tween.set_parallel(false)
	tween.tween_callback(func() -> void: label.visible = false)


func _acquire() -> CPUParticles2D:
	var particles := _pool[_pool_index]
	_pool_index = (_pool_index + 1) % _pool.size()
	return particles
