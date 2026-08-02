extends EnemyBase
## THE HIGH-WATER MARK — Storm Surge Harbor's boss (GAME_DESIGN.md §12, §16).
##
## The third fight, and deliberately the third *shape*. The Inferno Adjuster is
## a ground bruiser you punish by stomping a stunned body. The Actuary never
## lands and asks where you are in the air. This one attacks the floor itself:
## it raises the tide, so the question is never "where is the boss" but "how
## much ground is left, and which ledge do I want to be on when it runs out".
##
## Its punish window follows from that. When the tide goes out it is beached —
## slumped on the floor, taking double, contact-safe — and the water it was
## standing in is gone, so the arena you were cornered on is briefly yours.
##
## Design rules it obeys, same as the other two:
##   - every attack telegraphs for at least TELL_FLOOR seconds before it can
##     hurt you (§16), and the tide's tell is the water visibly climbing
##   - never more than a readable number of projectiles alive at once
##   - each attack ends in a punish window reachable with the movement verbs
##     the game already taught (§33)
##   - three phases, each adding an idea rather than a bigger number

signal defeated

enum State { INTRO, IDLE, TIDE_TELL, TIDE, BREAKER_TELL, BREAKER,
		DELUGE_TELL, DELUGE, BEACHED, DYING }

## No attack may become dangerous sooner than this after it starts telegraphing
## (§16). tools/check_bosses.py reads it and every tell timing below out of
## this file and fails if any tell is shorter.
const TELL_FLOOR := 0.5

@export var fireball_scene: PackedScene
@export var arena_left: float = 120.0
@export var arena_right: float = 1480.0
@export var floor_y: float = 578.0
## Where it slumps for the punish window: on the floor, no platform needed.
@export var beached_y: float = 548.0
@export var perch_y: float = 400.0

# --- timings (seconds) ---
@export var idle_time: float = 0.9
@export var tide_tell: float = 0.9
@export var tide_time: float = 2.6
@export var breaker_tell: float = 0.75
@export var deluge_tell: float = 0.8
@export var beached_time: float = 1.8

# --- attack values ---
@export var tide_damage: int = 9
@export var tide_tick: float = 0.45
## How high the water climbs above the floor, per phase.
@export var tide_heights: Array[float] = [70.0, 110.0, 150.0]
@export var breaker_damage: int = 14
@export var breaker_speed: float = 420.0
@export var deluge_damage: int = 12
@export var deluge_speed: float = 210.0
@export var deluge_gravity: float = 200.0

@onready var visual: Node2D = $Visual
@onready var crest: Polygon2D = $Visual/Crest
@onready var tide_visual: Polygon2D = $Tide/TideVisual
@onready var tide_area: Area2D = $Tide/TideArea

var _state: int = State.INTRO
var _timer: float = 0.0
var _age: float = 0.0
var _player: Player = null
var _phase: int = 1
var _attack_index: int = 0
var _facing: int = -1
var _gravity: float = 1800.0
var _base_color: Color = Color(0.16, 0.52, 0.66)
## 0 while the water is out, 1 at full height. Drives both the visual and the
## hurt area, so what you can see and what can hurt you cannot disagree.
var _tide: float = 0.0
var _tide_damage_timer: float = 0.0


func _ready() -> void:
	always_active = true
	super._ready()
	var players := get_tree().get_nodes_in_group("player")
	if not players.is_empty():
		_player = players[0]
	_set_tide(0.0)
	_enter(State.INTRO, 1.2)
	Events.boss_spawned.emit("THE HIGH-WATER MARK", max_health)
	Events.boss_health_changed.emit(health, max_health)


func _physics_process(delta: float) -> void:
	_age += delta
	_timer -= delta
	_update_phase()
	_apply_tide_damage(delta)

	match _state:
		State.INTRO:
			_ride_swell(delta)
			if _timer <= 0.0:
				_enter(State.IDLE, idle_time)
		State.IDLE:
			_ride_swell(delta)
			_face_player()
			_drain_tide(delta)
			if _timer <= 0.0:
				_choose_attack()
		State.TIDE_TELL:
			# The tell IS the water climbing. Nothing else in this fight tells
			# you where to stand as clearly, so it is worth the whole window.
			_ride_swell(delta)
			_flash(0.7)
			_set_tide(1.0 - maxf(_timer, 0.0) / maxf(tide_tell, 0.001))
			if _timer <= 0.0:
				_enter(State.TIDE, tide_time)
		State.TIDE:
			_ride_swell(delta)
			_face_player()
			_set_tide(1.0)
			if _timer <= 0.0:
				_beach()
		State.BREAKER_TELL:
			_ride_swell(delta)
			_face_player()
			_flash(0.55)
			if _timer <= 0.0:
				_launch_breaker()
		State.BREAKER:
			_ride_swell(delta)
			if _timer <= 0.0:
				_beach()
		State.DELUGE_TELL:
			_climb_to(perch_y, delta)
			_flash(1.0)
			if _timer <= 0.0:
				_drop_deluge()
		State.DELUGE:
			_climb_to(perch_y, delta)
			if _timer <= 0.0:
				_beach()
		State.BEACHED:
			# Punish window: grounded, still, stompable, and the water is out.
			_drain_tide(delta)
			velocity.x = move_toward(velocity.x, 0.0, 900.0 * delta)
			velocity.y += _gravity * delta
			move_and_slide()
			visual.rotation = sin(_age * 22.0) * 0.1
			if _timer <= 0.0:
				visual.rotation = 0.0
				_enter(State.IDLE, idle_time)
		State.DYING:
			_drain_tide(delta)
			velocity.y += _gravity * delta
			move_and_slide()


# --- state helpers ----------------------------------------------------------

func _enter(state: int, timer: float) -> void:
	_state = state
	_timer = timer
	visual.modulate = Color.WHITE


## Rides its own swell: height follows the tide, so at full water it is high
## and out of stomp reach, and it comes down as the water drains.
func _ride_swell(delta: float) -> void:
	var target := floor_y - 96.0 - _tide * 90.0 + sin(_age * 2.0) * 14.0
	global_position.y = move_toward(global_position.y, target, 240.0 * delta)
	velocity = Vector2.ZERO


func _climb_to(height: float, delta: float) -> void:
	if is_instance_valid(_player):
		global_position.x = move_toward(
				global_position.x, _player.global_position.x, 300.0 * delta)
	global_position.x = clampf(global_position.x, arena_left, arena_right)
	global_position.y = move_toward(global_position.y, height, 380.0 * delta)
	velocity = Vector2.ZERO


func _face_player() -> void:
	if is_instance_valid(_player):
		_facing = 1 if _player.global_position.x > global_position.x else -1
	visual.scale.x = absf(visual.scale.x) * _facing


func _flash(rate_scale: float) -> void:
	var pulse := 0.5 + 0.5 * sin(_age * 30.0 * rate_scale)
	visual.modulate = _base_color.lerp(Color(1.8, 2.2, 2.4), pulse)
	crest.color = Color(0.7, 0.95, 1.0).lerp(Color(1, 1, 1), pulse)


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
		_base_color = [Color(0.16, 0.52, 0.66), Color(0.12, 0.44, 0.72),
				Color(0.10, 0.34, 0.80)][phase - 1]


func _choose_attack() -> void:
	# Rotate rather than randomise, so the fight is learnable (§16).
	_attack_index += 1
	var pattern := [State.TIDE_TELL, State.BREAKER_TELL, State.DELUGE_TELL]
	if _phase >= 2:
		pattern = [State.TIDE_TELL, State.BREAKER_TELL, State.DELUGE_TELL,
				State.BREAKER_TELL]
	var next: int = pattern[_attack_index % pattern.size()]
	# Phase speeds the tells up, but never below the telegraph floor: at phase
	# three a 0.5s tell scaled by 0.76 would be 0.38s, which is under the
	# reaction time the whole fight is designed around.
	var speed_scale := 1.0 - 0.12 * float(_phase - 1)
	match next:
		State.TIDE_TELL:
			_enter(State.TIDE_TELL, maxf(tide_tell * speed_scale, TELL_FLOOR))
		State.BREAKER_TELL:
			_enter(State.BREAKER_TELL, maxf(breaker_tell * speed_scale, TELL_FLOOR))
		State.DELUGE_TELL:
			_enter(State.DELUGE_TELL, maxf(deluge_tell * speed_scale, TELL_FLOOR))


func _beach() -> void:
	Sfx.play("land_hard")
	Juice.dust(global_position + Vector2(0.0, 40.0), 12)
	global_position.y = beached_y
	_enter(State.BEACHED, beached_time)


# --- the tide ---------------------------------------------------------------

## One number drives the water: the visual, the hurt area's height, and how
## high the boss rides. Nothing about the flood can be visible but harmless or
## harmful but invisible.
func _set_tide(value: float) -> void:
	_tide = clampf(value, 0.0, 1.0)
	var height := tide_heights[mini(_phase - 1, tide_heights.size() - 1)] * _tide
	tide_visual.scale.y = maxf(height / 100.0, 0.001)
	tide_area.position.y = -height * 0.5
	tide_area.scale.y = maxf(height / 100.0, 0.001)
	tide_visual.color = Color(0.24, 0.62, 0.86, 0.55 + 0.2 * _tide)


func _drain_tide(delta: float) -> void:
	if _tide > 0.0:
		_set_tide(_tide - delta * 1.6)


## Standing in the water hurts on a tick rather than continuously, so wading a
## step through a corner costs you something without being a death sentence.
func _apply_tide_damage(delta: float) -> void:
	_tide_damage_timer = maxf(_tide_damage_timer - delta, 0.0)
	if _tide <= 0.35 or _tide_damage_timer > 0.0:
		return
	for body in tide_area.get_overlapping_bodies():
		if body is Player:
			body.hurt(tide_damage, "drowned by the High-Water Mark")
			_tide_damage_timer = tide_tick


# --- attacks ----------------------------------------------------------------

## BREAKER: a wave that crosses the arena at ankle height. Answer: jump it, or
## be on a ledge already because the tide put you there.
func _launch_breaker() -> void:
	if fireball_scene == null:
		_beach()
		return
	var count := 2 + _phase
	var parent := get_parent()
	var from_left := _facing > 0
	var start_x := arena_left + 30.0 if from_left else arena_right - 30.0
	var direction := 1.0 if from_left else -1.0
	for i in count:
		var wave: Node2D = fireball_scene.instantiate()
		parent.add_child(wave)
		wave.launch(Vector2(start_x - direction * float(i) * 90.0, floor_y - 22.0),
				Vector2(direction * breaker_speed, 0.0), breaker_damage)
	Sfx.play("dash", 0.05, 0.9)
	Juice.shake(5.0, 0.25)
	_enter(State.BREAKER, 1.1)


## DELUGE: rain from the perch, in a spread with a gap. Answer: read the gap.
func _drop_deluge() -> void:
	if fireball_scene == null:
		_beach()
		return
	var count := 3 + _phase
	var parent := get_parent()
	var spread := 140.0
	for i in count:
		# The middle column is skipped from phase two: the gap is the answer,
		# and it moves with the boss because the boss tracked you to get here.
		if _phase >= 2 and i == count / 2:
			continue
		var offset := (float(i) - float(count - 1) * 0.5) * spread
		var drop: Node2D = fireball_scene.instantiate()
		parent.add_child(drop)
		drop.launch(global_position + Vector2(offset, 40.0),
				Vector2(0.0, deluge_speed), deluge_damage, deluge_gravity)
	Sfx.play("charged_shot", 0.1, 0.85)
	_enter(State.DELUGE, 0.6)


# --- damage -----------------------------------------------------------------

func _on_hitbox_body_entered(body: Node2D) -> void:
	# Contact only hurts while it is working. The punish window is safe to be
	# inside, which is what makes it a window rather than a bluff.
	if _state in [State.BEACHED, State.INTRO, State.DYING]:
		return
	super._on_hitbox_body_entered(body)


func take_damage(amount: int) -> void:
	if _state == State.DYING:
		return
	# Beached means exposed: it is worth waiting for the window.
	super.take_damage(amount * (2 if _state == State.BEACHED else 1))
	if health > 0:
		Events.boss_health_changed.emit(health, max_health)


func die() -> void:
	if _state == State.DYING:
		return
	_state = State.DYING
	_set_tide(0.0)
	Events.boss_health_changed.emit(0, max_health)
	GameManager.record_enemy_defeated()
	GameManager.record_boss_defeated()
	# Absorbing the boss's power is the reward for the fight (§12). Undertow is
	# this one's pull, turned around.
	GameManager.grant_ability(Abilities.UNDERTOW)
	Sfx.play("room_clear")
	Juice.shake(14.0, 0.9)
	Juice.hit_stop(0.12)
	Juice.enemy_death(global_position, Color(0.4, 0.8, 0.95))
	_drop_premiums()
	defeated.emit()
	queue_free()
