extends EnemyBase
## THE ACTUARY — the second boss (GAME_DESIGN.md §12, §16).
##
## Deliberately the opposite fight to the Inferno Adjuster. That one is a
## ground bruiser you punish by stomping a stunned body; this one never lands,
## and every attack asks a question about where you are in the *air* rather
## than where you are standing.
##
## It is also the fight that pays off the aiming pass: Risk Pool drops
## destructible liabilities overhead, and shooting up at them is both the
## fastest answer and the only one that does not cost you floor space.
##
## Design rules it obeys, same as the Inferno Adjuster:
##   - every attack telegraphs for at least 0.5s before it can hurt you (§16)
##   - never more than a readable number of projectiles alive at once
##   - each attack ends in a punish window — here it sinks to head height,
##     where the movement verbs you already have can reach it (§33)
##   - three phases, each adding an idea rather than a bigger number

signal defeated

enum State { INTRO, HOVER, PROJECT_TELL, PROJECT, POOL_TELL, POOL,
		AUDIT_TELL, AUDIT, EXPOSED, DYING }

@export var fireball_scene: PackedScene
@export var arena_left: float = 120.0
@export var arena_right: float = 1480.0
@export var floor_y: float = 578.0
## The height it sinks to when exposed: reachable from the ground with a
## double jump, so the punish never needs a platform you might not be near.
@export var exposed_y: float = 430.0
@export var high_y: float = 190.0

# --- timings (seconds) ---
@export var hover_time: float = 0.9
@export var project_tell: float = 0.85
@export var project_time: float = 0.45
@export var pool_tell: float = 0.7
@export var audit_tell: float = 0.8
@export var exposed_time: float = 1.7

# --- attack values ---
@export var beam_damage: int = 18
@export var orb_damage: int = 12
@export var ring_damage: int = 12
@export var orb_speed: float = 150.0
@export var orb_gravity: float = 240.0
@export var ring_speed: float = 260.0

@onready var visual: Node2D = $Visual
@onready var lens: Polygon2D = $Visual/Lens
@onready var halo: Node2D = $Visual/Halo
@onready var beam: Node2D = $Beam
@onready var beam_visual: Polygon2D = $Beam/BeamVisual
@onready var beam_area: Area2D = $Beam/BeamArea

var _state: int = State.INTRO
var _timer: float = 0.0
var _age: float = 0.0
var _player: Player = null
var _phase: int = 1
var _attack_index: int = 0
var _beam_y: float = 0.0
var _beam_hit: bool = false
var _base_color: Color = Color(0.36, 0.62, 0.95)


func _ready() -> void:
	always_active = true
	super._ready()
	var players := get_tree().get_nodes_in_group("player")
	if not players.is_empty():
		_player = players[0]
	_set_beam(false)
	_enter(State.INTRO, 1.2)
	Events.boss_spawned.emit("THE ACTUARY", max_health)
	Events.boss_health_changed.emit(health, max_health)


func _physics_process(delta: float) -> void:
	_age += delta
	_timer -= delta
	halo.rotation += delta * (1.6 + 0.8 * float(_phase))
	_update_phase()

	match _state:
		State.INTRO:
			_drift_to(Vector2(_centre_x(), high_y), delta, 200.0)
			if _timer <= 0.0:
				_enter(State.HOVER, hover_time)
		State.HOVER:
			_bob(delta)
			if _timer <= 0.0:
				_choose_attack()
		State.PROJECT_TELL:
			# The tell is the line itself: it locks to your height the instant
			# the attack starts, so the answer is always "stop being there".
			_drift_to(Vector2(_centre_x(), high_y), delta, 260.0)
			_flash(0.9)
			_pulse_beam()
			if _timer <= 0.0:
				_fire_beam()
		State.PROJECT:
			if _timer <= 0.0:
				_set_beam(false)
				_enter(State.EXPOSED, exposed_time)
		State.POOL_TELL:
			_track_above_player(delta)
			_flash(0.7)
			if _timer <= 0.0:
				_drop_pool()
		State.POOL:
			_bob(delta)
			if _timer <= 0.0:
				_enter(State.EXPOSED, exposed_time)
		State.AUDIT_TELL:
			_drift_to(Vector2(_centre_x(), (high_y + exposed_y) * 0.5), delta, 320.0)
			_flash(0.55)
			if _timer <= 0.0:
				_fire_ring()
		State.AUDIT:
			if _timer <= 0.0:
				_enter(State.EXPOSED, exposed_time)
		State.EXPOSED:
			# Punish window: it sinks into reach and stops calculating.
			_drift_to(Vector2(global_position.x, exposed_y), delta, 300.0)
			visual.rotation = sin(_age * 18.0) * 0.09
			lens.color = Color(1.0, 0.55, 0.45)
			if _timer <= 0.0:
				visual.rotation = 0.0
				_enter(State.HOVER, hover_time)
		State.DYING:
			global_position.y += 260.0 * delta
			visual.rotation += delta * 5.0


# --- movement helpers -------------------------------------------------------

func _centre_x() -> float:
	return (arena_left + arena_right) * 0.5


func _drift_to(target: Vector2, delta: float, speed: float) -> void:
	global_position.x = move_toward(global_position.x,
			clampf(target.x, arena_left, arena_right), speed * delta)
	global_position.y = move_toward(global_position.y, target.y, speed * delta)
	velocity = Vector2.ZERO


func _bob(delta: float) -> void:
	_drift_to(Vector2(global_position.x, high_y + sin(_age * 2.0) * 22.0), delta, 200.0)


func _track_above_player(delta: float) -> void:
	var target_x := _player.global_position.x if is_instance_valid(_player) else global_position.x
	_drift_to(Vector2(target_x, high_y), delta, 380.0)


func _enter(state: int, timer: float) -> void:
	_state = state
	_timer = timer
	visual.modulate = Color.WHITE
	lens.color = Color(0.85, 0.95, 1.0)


func _flash(rate_scale: float) -> void:
	var pulse := 0.5 + 0.5 * sin(_age * 30.0 * rate_scale)
	visual.modulate = _base_color.lerp(Color(2.0, 2.2, 2.4), pulse)
	lens.color = Color(1.0, 0.9, 0.5).lerp(Color(1, 1, 1), pulse)


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
		_base_color = [Color(0.36, 0.62, 0.95), Color(0.45, 0.5, 1.0),
				Color(0.72, 0.42, 1.0)][phase - 1]


func _choose_attack() -> void:
	# Rotates rather than randomises, so the fight is learnable (§16).
	_attack_index += 1
	var pattern := [State.PROJECT_TELL, State.POOL_TELL, State.AUDIT_TELL]
	if _phase >= 2:
		pattern = [State.PROJECT_TELL, State.POOL_TELL, State.PROJECT_TELL, State.AUDIT_TELL]
	var next: int = pattern[_attack_index % pattern.size()]
	var speed_scale := 1.0 - 0.12 * float(_phase - 1)
	match next:
		State.PROJECT_TELL:
			_enter(State.PROJECT_TELL, project_tell * speed_scale)
			_beam_y = _player.global_position.y if is_instance_valid(_player) else floor_y - 60.0
			_beam_hit = false
			_place_beam()
			_set_beam(true, false)
		State.POOL_TELL:
			_enter(State.POOL_TELL, pool_tell * speed_scale)
		State.AUDIT_TELL:
			_enter(State.AUDIT_TELL, audit_tell * speed_scale)


# --- attacks ----------------------------------------------------------------

## PROJECTION: a horizontal beam at the height you were standing at when it
## started. Answer: change your height. Any height. It does not track.
func _place_beam() -> void:
	beam.global_position = Vector2(_centre_x(), clampf(_beam_y, high_y, floor_y - 20.0))
	beam_visual.scale = Vector2(1.0, 0.12)


func _pulse_beam() -> void:
	var pulse := 0.5 + 0.5 * sin(_age * 26.0)
	beam_visual.color = Color(1.0, 0.85, 0.4, 0.25 + 0.35 * pulse)


func _fire_beam() -> void:
	beam_visual.scale = Vector2(1.0, 1.0)
	beam_visual.color = Color(1.0, 0.95, 0.75, 0.95)
	_set_beam(true, true)
	Sfx.play("charged_shot")
	Juice.shake(6.0, 0.3)
	_enter(State.PROJECT, project_time)


func _set_beam(shown: bool, lethal: bool = false) -> void:
	beam.visible = shown
	beam_area.set_deferred("monitoring", shown and lethal)


func _on_beam_body_entered(body: Node2D) -> void:
	if _beam_hit or not body is Player:
		return
	_beam_hit = true
	body.hurt(beam_damage, "cited by the Actuary")


## RISK POOL: slow liabilities dropped overhead. They are destructible, and
## shooting up at them is the answer the aiming pass exists to make possible.
func _drop_pool() -> void:
	if fireball_scene == null:
		_enter(State.EXPOSED, exposed_time)
		return
	var count := 3 + _phase
	var parent := get_parent()
	var spread := 150.0
	for i in count:
		var offset := (float(i) - float(count - 1) * 0.5) * spread
		var orb: Node2D = fireball_scene.instantiate()
		parent.add_child(orb)
		orb.launch(global_position + Vector2(offset, 40.0),
				Vector2(0.0, orb_speed), orb_damage, orb_gravity)
	Sfx.play("flame_draft", 0.1, 0.8)
	_enter(State.POOL, 0.5)


## AUDIT: a ring outward from the centre. Answer: be in a gap, or dash one.
func _fire_ring() -> void:
	if fireball_scene == null:
		_enter(State.EXPOSED, exposed_time)
		return
	var count := 8 + 2 * _phase
	var parent := get_parent()
	for i in count:
		var angle := TAU * float(i) / float(count)
		var direction := Vector2.RIGHT.rotated(angle)
		var shot: Node2D = fireball_scene.instantiate()
		parent.add_child(shot)
		shot.launch(global_position + direction * 46.0, direction * ring_speed, ring_damage)
	Sfx.play("charged_shot", 0.1, 0.9)
	Juice.shake(5.0, 0.25)
	_enter(State.AUDIT, 0.5)


# --- damage -----------------------------------------------------------------

func _on_hitbox_body_entered(body: Node2D) -> void:
	# Contact only hurts while it is working. The punish window is safe to be
	# inside, which is what makes it a window rather than a bluff.
	if _state in [State.EXPOSED, State.INTRO, State.DYING]:
		return
	super._on_hitbox_body_entered(body)


func take_damage(amount: int) -> void:
	if _state == State.DYING:
		return
	super.take_damage(amount * (2 if _state == State.EXPOSED else 1))
	if health > 0:
		Events.boss_health_changed.emit(health, max_health)


func die() -> void:
	if _state == State.DYING:
		return
	_state = State.DYING
	_set_beam(false)
	Events.boss_health_changed.emit(0, max_health)
	GameManager.record_enemy_defeated()
	# Absorbing the boss's power is the reward for the fight (§12), and the
	# second ability is what unlocks a combination (§14).
	GameManager.grant_ability(Abilities.IMPACT_DASH)
	Sfx.play("room_clear")
	Juice.shake(14.0, 0.9)
	Juice.hit_stop(0.12)
	Juice.enemy_death(global_position, Color(0.6, 0.75, 1.0))
	_drop_premiums()
	defeated.emit()
	queue_free()
