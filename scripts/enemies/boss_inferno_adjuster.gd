extends EnemyBase
## THE INFERNO ADJUSTER — Blaze Borough's boss (GAME_DESIGN.md §12).
##
## Design rules this fight obeys:
##   - every attack telegraphs for at least 0.5s before it can hurt you (§16)
##   - never more than 5 projectiles alive at once, all big and high contrast
##   - each attack ends in a punish window where the boss is stompable, so the
##     movement verbs the game taught you are the answer (§33)
##   - three phases keyed to health, each adding one idea rather than raising
##     numbers

signal defeated

enum State { INTRO, IDLE, VOLLEY_TELL, VOLLEY, SLAM_RISE, SLAM_DROP, CHARGE_TELL, CHARGE, STUNNED, DYING }

@export var fireball_scene: PackedScene
@export var arena_left: float = 120.0
@export var arena_right: float = 1480.0
@export var floor_y: float = 578.0

# --- timings (seconds) ---
@export var idle_time: float = 1.0
@export var volley_tell: float = 0.7
@export var slam_hover: float = 0.6
@export var charge_tell: float = 0.8
@export var stun_time: float = 1.6

# --- attack values ---
@export var fireball_damage: int = 12
@export var fireball_speed: float = 300.0
@export var slam_damage: int = 16
@export var charge_speed: float = 620.0

@onready var visual: Node2D = $Visual
@onready var eye: Polygon2D = $Visual/Eye
@onready var slam_area: Area2D = $SlamArea

var _state: int = State.INTRO
var _timer: float = 0.0
var _age: float = 0.0
var _player: Player = null
var _phase: int = 1
var _attack_index: int = 0
var _facing: int = -1
var _gravity: float = 1800.0
var _base_color: Color = Color(0.86, 0.28, 0.16)


func _ready() -> void:
	always_active = true
	super._ready()
	var players := get_tree().get_nodes_in_group("player")
	if not players.is_empty():
		_player = players[0]
	_enter(State.INTRO, 1.2)
	Events.boss_spawned.emit("THE INFERNO ADJUSTER", max_health)
	Events.boss_health_changed.emit(health, max_health)


func _physics_process(delta: float) -> void:
	_age += delta
	_timer -= delta
	_update_phase()

	match _state:
		State.INTRO:
			_hover_bob(delta)
			if _timer <= 0.0:
				_enter(State.IDLE, idle_time)
		State.IDLE:
			_hover_bob(delta)
			_face_player()
			if _timer <= 0.0:
				_choose_attack()
		State.VOLLEY_TELL:
			_hover_bob(delta)
			_flash(0.75)
			if _timer <= 0.0:
				_fire_volley()
		State.VOLLEY:
			_hover_bob(delta)
			if _timer <= 0.0:
				_enter(State.STUNNED, stun_time * 0.6)
		State.SLAM_RISE:
			# Hangs directly above the player: the tell is positional, not
			# just visual, so you learn to keep moving.
			_track_above_player(delta)
			_flash(1.0)
			if _timer <= 0.0:
				_enter(State.SLAM_DROP, 2.0)
		State.SLAM_DROP:
			velocity.y += _gravity * delta
			velocity.x = 0.0
			move_and_slide()
			if is_on_floor():
				_land_slam()
		State.CHARGE_TELL:
			_hover_bob(delta)
			_face_player()
			_flash(0.55)
			if _timer <= 0.0:
				_start_charge()
		State.CHARGE:
			velocity = Vector2(_facing * charge_speed, 0.0)
			move_and_slide()
			if global_position.x <= arena_left or global_position.x >= arena_right or is_on_wall():
				_end_charge()
			elif _timer <= 0.0:
				_end_charge()
		State.STUNNED:
			# Punish window: grounded, still, and stompable.
			velocity.x = move_toward(velocity.x, 0.0, 900.0 * delta)
			velocity.y += _gravity * delta
			move_and_slide()
			visual.rotation = sin(_age * 26.0) * 0.12
			if _timer <= 0.0:
				visual.rotation = 0.0
				_enter(State.IDLE, idle_time)
		State.DYING:
			velocity.y += _gravity * delta
			move_and_slide()


# --- state helpers ----------------------------------------------------------

func _enter(state: int, timer: float) -> void:
	_state = state
	_timer = timer
	visual.modulate = Color.WHITE


func _hover_bob(delta: float) -> void:
	var target := floor_y - 120.0 + sin(_age * 2.2) * 18.0
	global_position.y = move_toward(global_position.y, target, 220.0 * delta)
	velocity = Vector2.ZERO


func _track_above_player(delta: float) -> void:
	if is_instance_valid(_player):
		global_position.x = move_toward(
				global_position.x, _player.global_position.x, 420.0 * delta)
	global_position.x = clampf(global_position.x, arena_left, arena_right)
	global_position.y = move_toward(global_position.y, floor_y - 220.0, 420.0 * delta)
	velocity = Vector2.ZERO


func _face_player() -> void:
	if is_instance_valid(_player):
		_facing = 1 if _player.global_position.x > global_position.x else -1
	visual.scale.x = absf(visual.scale.x) * _facing


## Pulsing white flash is the universal "something is coming" tell.
func _flash(rate_scale: float) -> void:
	var pulse := 0.5 + 0.5 * sin(_age * 30.0 * rate_scale)
	visual.modulate = _base_color.lerp(Color(2.2, 2.0, 1.6), pulse)
	eye.color = Color(1.0, 0.95, 0.6).lerp(Color(1, 1, 1), pulse)


func _update_phase() -> void:
	var ratio := float(health) / float(max_health)
	var phase := 1
	if ratio <= 0.33:
		phase = 3
	elif ratio <= 0.66:
		phase = 2
	if phase != _phase:
		_phase = phase
		Juice.shake(7.0, 0.4)
		Sfx.play("low_coverage", 0.0)
		_base_color = [Color(0.86, 0.28, 0.16), Color(0.92, 0.36, 0.12),
				Color(1.0, 0.5, 0.1)][phase - 1]


func _choose_attack() -> void:
	# Rotate rather than randomise, so the fight is learnable (§16).
	_attack_index += 1
	var pattern := [State.VOLLEY_TELL, State.SLAM_RISE, State.CHARGE_TELL]
	if _phase >= 2:
		pattern = [State.VOLLEY_TELL, State.SLAM_RISE, State.VOLLEY_TELL, State.CHARGE_TELL]
	var next: int = pattern[_attack_index % pattern.size()]
	var speed_scale := 1.0 - 0.12 * float(_phase - 1)
	match next:
		State.VOLLEY_TELL:
			_enter(State.VOLLEY_TELL, volley_tell * speed_scale)
		State.SLAM_RISE:
			_enter(State.SLAM_RISE, slam_hover * speed_scale)
		State.CHARGE_TELL:
			_enter(State.CHARGE_TELL, charge_tell * speed_scale)


# --- attacks ----------------------------------------------------------------

func _fire_volley() -> void:
	if fireball_scene == null or not is_instance_valid(_player):
		_enter(State.STUNNED, stun_time * 0.6)
		return
	var count := 3 if _phase == 1 else (4 if _phase == 2 else 5)
	var to_player := (_player.global_position - global_position).normalized()
	var spread := deg_to_rad(14.0)
	var parent := get_parent()
	for i in count:
		var offset := (float(i) - float(count - 1) * 0.5) * spread
		var direction := to_player.rotated(offset)
		var ball: Node2D = fireball_scene.instantiate()
		parent.add_child(ball)
		ball.launch(global_position + direction * 40.0,
				direction * fireball_speed, fireball_damage)
	Sfx.play("flame_draft")
	Juice.shake(4.0, 0.2)
	_enter(State.VOLLEY, 0.35)


func _land_slam() -> void:
	Sfx.play("pound_impact")
	Juice.shockwave(global_position + Vector2(0.0, 40.0))
	Juice.shake(11.0, 0.45)
	Juice.hit_stop(0.06)
	for body in slam_area.get_overlapping_bodies():
		if body is Player:
			body.hurt(slam_damage, "flattened by the Inferno Adjuster")
	_enter(State.STUNNED, stun_time)


func _start_charge() -> void:
	Sfx.play("dash", 0.05)
	global_position.y = floor_y
	_enter(State.CHARGE, 2.0)


func _end_charge() -> void:
	Sfx.play("land_hard")
	Juice.shake(8.0, 0.3)
	Juice.dust(global_position + Vector2(0.0, 30.0), 14)
	_enter(State.STUNNED, stun_time)


# --- damage -----------------------------------------------------------------

func _on_hitbox_body_entered(body: Node2D) -> void:
	# Contact only hurts while actively attacking, so the punish window is
	# genuinely safe to stand in.
	if _state in [State.STUNNED, State.INTRO, State.DYING]:
		return
	super._on_hitbox_body_entered(body)


func take_damage(amount: int) -> void:
	if _state == State.DYING:
		return
	# Stunned means exposed: it is worth waiting for the window.
	var scaled := amount * (2 if _state == State.STUNNED else 1)
	super.take_damage(scaled)
	if health > 0:
		Events.boss_health_changed.emit(health, max_health)


func die() -> void:
	if _state == State.DYING:
		return
	_state = State.DYING
	Events.boss_health_changed.emit(0, max_health)
	GameManager.record_enemy_defeated()
	GameManager.record_boss_defeated()
	# Absorbing the boss's power is the reward for the fight (§12), and the
	# second ability is what unlocks a combination (§14).
	GameManager.grant_ability(Abilities.IMPACT_DASH)
	Sfx.play("room_clear")
	Juice.shake(14.0, 0.9)
	Juice.hit_stop(0.12)
	Juice.enemy_death(global_position, Color(1.0, 0.55, 0.2))
	_drop_premiums()
	defeated.emit()
	queue_free()
