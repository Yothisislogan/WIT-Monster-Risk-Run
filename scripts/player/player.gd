class_name Player
extends CharacterBody2D
## WIT Monster controller. Movement feel is the project's top priority
## (GAME_DESIGN.md §7, §35): quick acceleration, predictable air control,
## generous mobile input buffering, short powerful dash, clear wall cling.
## All timing constants are exported so they can be tuned on a real phone.
##
## Jump budget the levels are built against (tools/check_reachability.py
## enforces it). The closed form v^2/2g = 640^2/3000 = 136 px under-reports:
## the apex hang below adds ~6 px, so the real numbers are
##   single jump rise  = 143 px
##   double jump total = 261 px
##   flat gap (jump)   = 312 px, (jump + double) = 504 px, +130 px with dash
## Level design uses the conservative closed form, leaving built-in headroom.

# --- Ground movement ---
@export var move_speed: float = 360.0
@export var ground_accel: float = 3000.0
@export var ground_friction: float = 3400.0
@export var air_accel: float = 2100.0

# --- Jumping (buffers per §6: jump 120-180ms, coyote 100-150ms) ---
@export var jump_velocity: float = -640.0
@export var double_jump_velocity: float = -580.0
@export var max_air_jumps: int = 1
@export var jump_cut_multiplier: float = 0.45
## Asymmetric gravity: float up, fall fast. Reads snappy instead of moon-like.
@export var rise_gravity: float = 1500.0
@export var fall_gravity: float = 2100.0
## Extra float at the top of the arc so precise landings are forgiving.
@export var apex_threshold: float = 90.0
@export var apex_gravity_scale: float = 0.6
@export var max_fall_speed: float = 1000.0
@export var coyote_time: float = 0.12
@export var jump_buffer_time: float = 0.15

# --- Dash (buffer ~100ms per §6) ---
@export var dash_speed: float = 780.0
@export var dash_duration: float = 0.16
@export var dash_cooldown: float = 0.35
@export var dash_buffer_time: float = 0.10

# --- Wall interaction ---
@export var wall_slide_speed: float = 90.0
@export var wall_jump_velocity: Vector2 = Vector2(400.0, -560.0)
@export var wall_coyote_time: float = 0.10

# --- Ground pound / belly bounce (§7) ---
@export var pound_speed: float = 1500.0
@export var pound_hang_time: float = 0.09
@export var pound_damage: int = 40
@export var pound_bounce_velocity: float = -420.0

# --- Stomping enemies ---
@export var stomp_damage: int = 15
@export var stomp_bounce_velocity: float = -460.0
@export var stomp_bounce_held_velocity: float = -600.0

# --- Base weapon: tap to shoot, hold to charge (§7) ---
@export var fire_cooldown: float = 0.18
@export var charge_time: float = 0.5
@export var projectile_damage: int = 10
@export var charged_damage: int = 30

# --- Damage response ---
@export var invulnerability_time: float = 0.8
@export var hurt_knockback: Vector2 = Vector2(260.0, -300.0)

# --- Flame Draft (equipped boss ability, §12) ---
@export var flame_damage: int = 25

@onready var sprite: Node2D = $Sprite
@onready var muzzle: Marker2D = $Muzzle
@onready var projectile_pool: Node = $ProjectilePool
@onready var flame_pool: Node = $FlamePool
@onready var munch_area: Area2D = $MunchArea
@onready var stomp_area: Area2D = $StompArea
@onready var pound_area: Area2D = $PoundArea

var facing: int = 1
var coyote_timer: float = 0.0
var jump_buffer_timer: float = 0.0
var dash_buffer_timer: float = 0.0
var wall_coyote_timer: float = 0.0
var last_wall_normal: float = 0.0

var air_jumps_left: int = 0

var dashing: bool = false
var dash_timer: float = 0.0
var dash_cooldown_timer: float = 0.0
var air_dash_available: bool = true

var pounding: bool = false
var pound_hang_timer: float = 0.0

var charging: bool = false
var charge_timer: float = 0.0
var fire_timer: float = 0.0

var invulnerability_timer: float = 0.0
var base_sprite_scale: Vector2 = Vector2.ONE
var _squash: Vector2 = Vector2.ONE
var _was_on_floor: bool = true
var _fall_speed: float = 0.0


var auto_fire: bool = false
var _surface_friction: float = 1.0
var _surface_accel: float = 1.0


func _ready() -> void:
	base_sprite_scale = sprite.scale.abs()
	auto_fire = bool(Settings.get_value("auto_fire"))
	Settings.changed.connect(func(key: String, value: Variant) -> void:
		if key == "auto_fire":
			auto_fire = bool(value))


## Rooms clamp the camera so the void outside the level is never on screen.
func apply_camera_bounds(bounds: Rect2) -> void:
	var camera: Camera2D = $Camera
	camera.limit_left = int(bounds.position.x)
	camera.limit_top = int(bounds.position.y)
	camera.limit_right = int(bounds.position.x + bounds.size.x)
	camera.limit_bottom = int(bounds.position.y + bounds.size.y)
	camera.reset_smoothing()


func _physics_process(delta: float) -> void:
	_surface_friction = 1.0
	_surface_accel = 1.0
	_update_timers(delta)
	_read_action_buffers()

	if dashing:
		_process_dash(delta)
	elif pounding:
		_process_pound(delta)
	else:
		_apply_gravity(delta)
		_process_walk(delta)
		_process_wall(delta)
		_try_jump()
		_try_dash()
		_try_pound()

	_process_weapon(delta)
	_process_ability()
	_process_munch()

	_fall_speed = velocity.y
	move_and_slide()
	_process_stomp()
	_after_move()
	_update_visuals(delta)


func _update_timers(delta: float) -> void:
	coyote_timer = maxf(coyote_timer - delta, 0.0)
	jump_buffer_timer = maxf(jump_buffer_timer - delta, 0.0)
	dash_buffer_timer = maxf(dash_buffer_timer - delta, 0.0)
	wall_coyote_timer = maxf(wall_coyote_timer - delta, 0.0)
	dash_cooldown_timer = maxf(dash_cooldown_timer - delta, 0.0)
	fire_timer = maxf(fire_timer - delta, 0.0)
	invulnerability_timer = maxf(invulnerability_timer - delta, 0.0)


func _read_action_buffers() -> void:
	if Input.is_action_just_pressed("jump"):
		jump_buffer_timer = jump_buffer_time
	if Input.is_action_just_pressed("dash"):
		dash_buffer_timer = dash_buffer_time


func _apply_gravity(delta: float) -> void:
	if not is_on_floor():
		var g := rise_gravity if velocity.y < 0.0 else fall_gravity
		# Hang briefly at the apex — the single biggest "feels good" trick.
		if absf(velocity.y) < apex_threshold:
			g *= apex_gravity_scale
		velocity.y = minf(velocity.y + g * delta, max_fall_speed)
	# Variable jump height: releasing jump early cuts upward velocity.
	if velocity.y < 0.0 and Input.is_action_just_released("jump"):
		velocity.y *= jump_cut_multiplier


## Cards can raise these, so read them fresh rather than caching.
func _speed() -> float:
	return move_speed * GameManager.factor("move_speed_mult")


func _max_air_jumps() -> int:
	return max_air_jumps + _bonus_air_jumps()


func _bonus_air_jumps() -> int:
	return int(GameManager.stat("air_jumps"))


## Slippery surfaces call this every frame they are underfoot. It only ever
## reduces grip, and it resets each frame so stepping off restores control.
func apply_surface(friction_mult: float, accel_mult: float) -> void:
	_surface_friction = minf(_surface_friction, friction_mult)
	_surface_accel = minf(_surface_accel, accel_mult)


func _process_walk(delta: float) -> void:
	var direction := Input.get_axis("move_left", "move_right")
	if direction != 0.0:
		facing = 1 if direction > 0.0 else -1
		var accel := ground_accel if is_on_floor() else air_accel
		if is_on_floor():
			accel *= _surface_accel
		velocity.x = move_toward(velocity.x, direction * _speed(), accel * delta)
	elif is_on_floor():
		velocity.x = move_toward(velocity.x, 0.0, ground_friction * _surface_friction * delta)


func _process_wall(delta: float) -> void:
	if is_on_wall_only() and _pressing_into_wall() and velocity.y > 0.0:
		# Wall cling: slow slide while holding toward the wall.
		velocity.y = minf(velocity.y, wall_slide_speed)
		wall_coyote_timer = wall_coyote_time
		last_wall_normal = get_wall_normal().x
		# Touching a wall refreshes the air jump so wall chains stay expressive.
		air_jumps_left = _max_air_jumps()


func _pressing_into_wall() -> bool:
	var direction := Input.get_axis("move_left", "move_right")
	return direction != 0.0 and signf(direction) == -signf(get_wall_normal().x)


func _try_jump() -> void:
	if jump_buffer_timer <= 0.0:
		return
	if is_on_floor() or coyote_timer > 0.0:
		_do_jump(jump_velocity * GameManager.factor("jump_mult"))
		Sfx.play("jump")
		Juice.jump_puff(_feet_position())
		_squash = Vector2(0.82, 1.22)
	elif wall_coyote_timer > 0.0:
		# Wall jump: push away from the last clung wall.
		velocity.x = wall_jump_velocity.x * last_wall_normal
		velocity.y = wall_jump_velocity.y
		facing = 1 if last_wall_normal > 0.0 else -1
		jump_buffer_timer = 0.0
		wall_coyote_timer = 0.0
		Sfx.play("wall_jump")
		Juice.jump_puff(global_position)
		_squash = Vector2(0.85, 1.18)
	elif air_jumps_left > 0 or _bonus_air_jumps() > 0:
		# Double jump: hard reset of vertical speed so it always feels the same,
		# whether tapped at the apex or during a long fall.
		air_jumps_left -= 1
		_do_jump(double_jump_velocity * GameManager.factor("jump_mult"))
		Sfx.play("double_jump")
		Juice.double_jump_ring(global_position)
		Juice.shake(2.0, 0.12)
		_squash = Vector2(0.75, 1.3)


func _do_jump(power: float) -> void:
	velocity.y = power
	jump_buffer_timer = 0.0
	coyote_timer = 0.0


func _try_dash() -> void:
	if dash_buffer_timer <= 0.0 or dash_cooldown_timer > 0.0:
		return
	if not is_on_floor() and not air_dash_available:
		return
	dashing = true
	dash_timer = dash_duration
	dash_buffer_timer = 0.0
	dash_cooldown_timer = dash_cooldown * GameManager.factor("dash_cooldown_mult")
	if not is_on_floor():
		air_dash_available = false
	var direction := Input.get_axis("move_left", "move_right")
	if direction != 0.0:
		facing = 1 if direction > 0.0 else -1
	velocity = Vector2(facing * dash_speed, 0.0)
	# Dashing grants brief protection so it reads as powerful and reckless.
	invulnerability_timer = maxf(invulnerability_timer, dash_duration)
	Sfx.play("dash")
	Juice.dust(_feet_position(), 10)
	Juice.shake(3.0, 0.15)
	_squash = Vector2(1.35, 0.7)


func _process_dash(delta: float) -> void:
	dash_timer -= delta
	velocity.y = 0.0
	if dash_timer <= 0.0 or is_on_wall():
		dashing = false
		velocity.x = facing * move_speed


## Ground pound: hold down and press jump while airborne (§7 belly bounce).
func _try_pound() -> void:
	if is_on_floor() or jump_buffer_timer <= 0.0:
		return
	if not Input.is_action_pressed("move_down"):
		return
	pounding = true
	pound_hang_timer = pound_hang_time
	jump_buffer_timer = 0.0
	velocity = Vector2.ZERO
	_squash = Vector2(1.3, 0.75)


func _process_pound(delta: float) -> void:
	# Brief hang before the slam sells the wind-up and telegraphs it.
	if pound_hang_timer > 0.0:
		pound_hang_timer -= delta
		velocity = Vector2.ZERO
		return
	velocity = Vector2(0.0, pound_speed)
	if is_on_floor():
		_land_pound()


func _land_pound() -> void:
	pounding = false
	velocity.y = 0.0
	Sfx.play("pound_impact")
	Juice.shockwave(_feet_position())
	Juice.shake(9.0, 0.35)
	Juice.hit_stop(0.06)
	_squash = Vector2(1.5, 0.55)
	# Shockwave damages everything grounded nearby and pops open crates.
	for body in pound_area.get_overlapping_bodies():
		if body.has_method("take_damage"):
			body.take_damage(pound_damage + int(GameManager.stat("pound_damage")))
	for area in pound_area.get_overlapping_areas():
		if area.has_method("shatter"):
			area.shatter()


## Landing on an enemy from above stomps it instead of hurting the player.
func _process_stomp() -> void:
	if pounding or _fall_speed <= 0.0:
		return
	for body in stomp_area.get_overlapping_bodies():
		if not body.has_method("take_damage"):
			continue
		if body.global_position.y < global_position.y:
			continue  # only stomp things below us
		body.take_damage(stomp_damage + int(GameManager.stat("stomp_damage")))
		# Holding jump gives a higher bounce — rewards deliberate chaining.
		var held := Input.is_action_pressed("jump")
		velocity.y = stomp_bounce_held_velocity if held else stomp_bounce_velocity
		air_jumps_left = _max_air_jumps()  # stomping refunds the double jump
		air_dash_available = true
		Sfx.play_chain("streak")
		Juice.hit_spark(body.global_position)
		Juice.shake(4.0, 0.18)
		Juice.hit_stop(0.045)
		_squash = Vector2(1.25, 0.8)
		# Brief i-frames so the enemy's contact hitbox does not also hurt us.
		invulnerability_timer = maxf(invulnerability_timer, 0.15)
		return


func _process_weapon(delta: float) -> void:
	# Auto-fire accessibility option: holding nothing still shoots (§22).
	if auto_fire and not charging and fire_timer <= 0.0 \
			and not Input.is_action_pressed("attack"):
		_fire(projectile_damage, false)
		Sfx.play("shoot", 0.08, 0.8)
	# Charging never blocks running or jumping (§7).
	if Input.is_action_just_pressed("attack") and fire_timer <= 0.0:
		charging = true
		charge_timer = 0.0
	if charging:
		var was_ready := charge_timer >= charge_time
		charge_timer += delta * GameManager.factor("charge_speed_mult")
		# One-shot cue the instant the shot is worth releasing.
		if not was_ready and charge_timer >= charge_time:
			Sfx.play("charge_ready", 0.02)
		Events.charge_changed.emit(minf(charge_timer / charge_time, 1.0))
		if Input.is_action_just_released("attack"):
			charging = false
			Events.charge_changed.emit(0.0)
			if charge_timer >= charge_time:
				_fire(charged_damage, true)
				Sfx.play("charged_shot")
				Juice.shake(3.5, 0.15)
			else:
				_fire(projectile_damage, false)
				Sfx.play("shoot")


func _fire(damage: int, pierce: bool) -> void:
	fire_timer = fire_cooldown * GameManager.factor("fire_rate_mult")
	var scaled := maxi(int(round(float(damage) * GameManager.factor("damage_mult"))), 1)
	var projectile: Node2D = projectile_pool.acquire()
	projectile.launch(muzzle.global_position, facing, scaled, pierce)


## Flame Draft: costs ability energy, pierces, and ignites what it hits.
func _process_ability() -> void:
	if not Input.is_action_just_pressed("special"):
		return
	if not GameManager.try_spend_ability_energy():
		return
	var flame: Node2D = flame_pool.acquire()
	flame.launch(muzzle.global_position, facing,
			int(round(float(flame_damage) * GameManager.factor("damage_mult"))), true)
	Sfx.play("flame_draft")
	Juice.shake(5.0, 0.2)
	_squash = Vector2(1.2, 0.85)


## Monster Munch: consume a nearby weakened enemy (§7).
func _process_munch() -> void:
	if not Input.is_action_just_pressed("munch"):
		return
	for body in munch_area.get_overlapping_bodies():
		if body.has_method("can_be_munched") and body.can_be_munched():
			Sfx.play("munch")
			Juice.enemy_death(body.global_position, Color(0.6, 1.0, 0.65))
			Juice.hit_stop(0.05)
			body.consume()
			_squash = Vector2(1.3, 0.78)
			return


## Bounce pads and other launchers call this.
func launch(power: float) -> void:
	velocity.y = -absf(power)
	air_jumps_left = _max_air_jumps()
	air_dash_available = true
	pounding = false
	_squash = Vector2(0.7, 1.35)
	Sfx.play("bounce")
	Juice.jump_puff(_feet_position())
	Juice.shake(3.0, 0.15)


func _after_move() -> void:
	var on_floor := is_on_floor()
	if on_floor:
		coyote_timer = coyote_time
		air_dash_available = true
		air_jumps_left = _max_air_jumps()
		if not _was_on_floor:
			_on_landed()
	_was_on_floor = on_floor


func _on_landed() -> void:
	var strength := clampf(_fall_speed / max_fall_speed, 0.0, 1.0)
	if strength > 0.6:
		Sfx.play("land_hard", 0.05)
	elif strength > 0.2:
		Sfx.play("land", 0.08, 0.7)
	if strength > 0.25:
		Juice.land_dust(_feet_position(), strength)
		_squash = Vector2(1.0 + 0.35 * strength, 1.0 - 0.3 * strength)
	if strength > 0.8:
		Juice.shake(3.0 * strength, 0.18)


func _feet_position() -> Vector2:
	return global_position + Vector2(0.0, 22.0)


func _update_visuals(delta: float) -> void:
	muzzle.position.x = absf(muzzle.position.x) * facing
	# Squash & stretch springs back toward rest every frame.
	_squash = _squash.lerp(Vector2.ONE, 1.0 - exp(-14.0 * delta))
	var stretch := _squash
	if not pounding and not dashing and charging and charge_timer >= charge_time:
		stretch.y *= 0.9
	sprite.scale = Vector2(
		base_sprite_scale.x * stretch.x * facing,
		base_sprite_scale.y * stretch.y
	)
	# Damage feedback: flash while invulnerable.
	if invulnerability_timer > 0.0 and not Juice.reduced_flashing:
		sprite.modulate.a = 0.4 if fmod(invulnerability_timer, 0.2) > 0.1 else 1.0
	else:
		sprite.modulate.a = 1.0


## Entry point for enemies and hazards. I-frames live here; run-level
## Coverage accounting lives in GameManager.
func hurt(amount: int, source: String) -> void:
	if invulnerability_timer > 0.0 or dashing:
		return
	invulnerability_timer = maxf(invulnerability_time + GameManager.stat("invuln_time"), 0.2)
	pounding = false
	velocity = Vector2(hurt_knockback.x * -facing, hurt_knockback.y)
	_squash = Vector2(1.3, 0.75)
	Sfx.play("player_hurt")
	Juice.shake(6.0, 0.3)
	Juice.hit_stop(0.05)
	GameManager.damage(amount, source)
