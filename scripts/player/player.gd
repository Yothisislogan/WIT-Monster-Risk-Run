class_name Player
extends CharacterBody2D
## WIT Monster controller. Movement feel is the project's top priority
## (GAME_DESIGN.md §7, §35): quick acceleration, predictable air control,
## generous mobile input buffering, short powerful dash, clear wall cling.
## All timing constants are exported so they can be tuned on a real phone.

# --- Ground movement ---
@export var move_speed: float = 340.0
@export var ground_accel: float = 2600.0
@export var ground_friction: float = 3400.0
@export var air_accel: float = 1900.0

# --- Jumping (buffers per §6: jump 120-180ms, coyote 100-150ms) ---
@export var jump_velocity: float = -540.0
@export var jump_cut_multiplier: float = 0.45
@export var gravity: float = 1500.0
@export var max_fall_speed: float = 950.0
@export var coyote_time: float = 0.12
@export var jump_buffer_time: float = 0.15

# --- Dash (buffer ~100ms per §6) ---
@export var dash_speed: float = 720.0
@export var dash_duration: float = 0.16
@export var dash_cooldown: float = 0.35
@export var dash_buffer_time: float = 0.10

# --- Wall interaction ---
@export var wall_slide_speed: float = 90.0
@export var wall_jump_velocity: Vector2 = Vector2(380.0, -500.0)
@export var wall_coyote_time: float = 0.10

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

var facing: int = 1
var coyote_timer: float = 0.0
var jump_buffer_timer: float = 0.0
var dash_buffer_timer: float = 0.0
var wall_coyote_timer: float = 0.0
var last_wall_normal: float = 0.0

var dashing: bool = false
var dash_timer: float = 0.0
var dash_cooldown_timer: float = 0.0
var air_dash_available: bool = true

var charging: bool = false
var charge_timer: float = 0.0
var fire_timer: float = 0.0

var invulnerability_timer: float = 0.0
var base_sprite_scale: Vector2 = Vector2.ONE
var _pop_tween: Tween


func _ready() -> void:
	base_sprite_scale = sprite.scale.abs()


func _physics_process(delta: float) -> void:
	_update_timers(delta)
	_read_action_buffers()

	if dashing:
		_process_dash(delta)
	else:
		_apply_gravity(delta)
		_process_walk(delta)
		_process_wall(delta)
		_try_jump()
		_try_dash()

	_process_weapon(delta)
	_process_ability()
	_process_munch()
	move_and_slide()
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
		velocity.y = minf(velocity.y + gravity * delta, max_fall_speed)
	# Variable jump height: releasing jump early cuts upward velocity.
	if velocity.y < 0.0 and Input.is_action_just_released("jump"):
		velocity.y *= jump_cut_multiplier


func _process_walk(delta: float) -> void:
	var direction := Input.get_axis("move_left", "move_right")
	if direction != 0.0:
		facing = 1 if direction > 0.0 else -1
		var accel := ground_accel if is_on_floor() else air_accel
		velocity.x = move_toward(velocity.x, direction * move_speed, accel * delta)
	elif is_on_floor():
		velocity.x = move_toward(velocity.x, 0.0, ground_friction * delta)


func _process_wall(delta: float) -> void:
	if is_on_wall_only() and _pressing_into_wall() and velocity.y > 0.0:
		# Wall cling: slow slide while holding toward the wall.
		velocity.y = minf(velocity.y, wall_slide_speed)
		wall_coyote_timer = wall_coyote_time
		last_wall_normal = get_wall_normal().x


func _pressing_into_wall() -> bool:
	var direction := Input.get_axis("move_left", "move_right")
	return direction != 0.0 and signf(direction) == -signf(get_wall_normal().x)


func _try_jump() -> void:
	if jump_buffer_timer <= 0.0:
		return
	if is_on_floor() or coyote_timer > 0.0:
		velocity.y = jump_velocity
		jump_buffer_timer = 0.0
		coyote_timer = 0.0
	elif wall_coyote_timer > 0.0:
		# Wall jump: push away from the last clung wall.
		velocity.x = wall_jump_velocity.x * last_wall_normal
		velocity.y = wall_jump_velocity.y
		facing = 1 if last_wall_normal > 0.0 else -1
		jump_buffer_timer = 0.0
		wall_coyote_timer = 0.0


func _try_dash() -> void:
	if dash_buffer_timer <= 0.0 or dash_cooldown_timer > 0.0:
		return
	if not is_on_floor() and not air_dash_available:
		return
	dashing = true
	dash_timer = dash_duration
	dash_buffer_timer = 0.0
	dash_cooldown_timer = dash_cooldown
	if not is_on_floor():
		air_dash_available = false
	var direction := Input.get_axis("move_left", "move_right")
	if direction != 0.0:
		facing = 1 if direction > 0.0 else -1
	velocity = Vector2(facing * dash_speed, 0.0)
	# Dashing grants brief protection so it reads as powerful and reckless.
	invulnerability_timer = maxf(invulnerability_timer, dash_duration)


func _process_dash(delta: float) -> void:
	dash_timer -= delta
	velocity.y = 0.0
	if dash_timer <= 0.0 or is_on_wall():
		dashing = false
		velocity.x = facing * move_speed


func _process_weapon(delta: float) -> void:
	# Charging never blocks running or jumping (§7).
	if Input.is_action_just_pressed("attack") and fire_timer <= 0.0:
		charging = true
		charge_timer = 0.0
	if charging:
		charge_timer += delta
		Events.charge_changed.emit(minf(charge_timer / charge_time, 1.0))
		if Input.is_action_just_released("attack"):
			charging = false
			Events.charge_changed.emit(0.0)
			if charge_timer >= charge_time:
				_fire(charged_damage, true)
			else:
				_fire(projectile_damage, false)


func _fire(damage: int, pierce: bool) -> void:
	fire_timer = fire_cooldown
	var projectile: Node2D = projectile_pool.acquire()
	projectile.launch(muzzle.global_position, facing, damage, pierce)


## Flame Draft: costs ability energy, pierces, and ignites what it hits.
func _process_ability() -> void:
	if not Input.is_action_just_pressed("special"):
		return
	if not GameManager.try_spend_ability_energy():
		return
	var flame: Node2D = flame_pool.acquire()
	flame.launch(muzzle.global_position, facing, flame_damage, true)


## Monster Munch: consume a nearby weakened enemy (§7).
func _process_munch() -> void:
	if not Input.is_action_just_pressed("munch"):
		return
	for body in munch_area.get_overlapping_bodies():
		if body.has_method("can_be_munched") and body.can_be_munched():
			body.consume()
			_munch_pop()
			return


func _munch_pop() -> void:
	sprite.scale = base_sprite_scale * Vector2(1.25 * facing, 0.8)
	_pop_tween = create_tween()
	_pop_tween.tween_property(sprite, "scale",
			Vector2(base_sprite_scale.x * facing, base_sprite_scale.y), 0.2)


func _after_move() -> void:
	if is_on_floor():
		coyote_timer = coyote_time
		air_dash_available = true


func _update_visuals(delta: float) -> void:
	muzzle.position.x = absf(muzzle.position.x) * facing
	var pop_active := _pop_tween != null and _pop_tween.is_running()
	if not pop_active:
		sprite.scale.x = base_sprite_scale.x * facing
	# Damage feedback: flash while invulnerable, squash slightly at full charge.
	if invulnerability_timer > 0.0:
		sprite.modulate.a = 0.4 if fmod(invulnerability_timer, 0.2) > 0.1 else 1.0
	else:
		sprite.modulate.a = 1.0
	if not pop_active:
		var squash := 0.85 if charging and charge_timer >= charge_time else 1.0
		sprite.scale.y = move_toward(sprite.scale.y, base_sprite_scale.y * squash, 2.0 * delta)


## Entry point for enemies and hazards. I-frames live here; run-level
## Coverage accounting lives in GameManager.
func hurt(amount: int, source: String) -> void:
	if invulnerability_timer > 0.0 or dashing:
		return
	invulnerability_timer = invulnerability_time
	velocity = Vector2(hurt_knockback.x * -facing, hurt_knockback.y)
	GameManager.damage(amount, source)
