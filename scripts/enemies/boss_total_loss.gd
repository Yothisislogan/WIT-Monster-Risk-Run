extends EnemyBase
## THE TOTAL LOSS — Crashway 5000's boss (GAME_DESIGN.md §12, §16).
##
## The fourth fight, and deliberately the fourth *shape*. The Inferno Adjuster
## is a bruiser you stomp. The Actuary never lands. The High-Water Mark floods
## the floor and then gives it back. This one keeps what it takes: it is a tow
## rig running the wreck lane, and every cycle it hauls one more standing
## platform out of the arena and does not return it. It is the only fight whose
## room is smaller at the end than it was at the start.
##
## That is what lets it ask for the verb no other boss asks for. The rig owns
## the floor plane — it never leaves it, and its sweep covers the lane end to
## end — so once the ledges are gone the only footing left is the two trailers
## hung under the overpass, and living on those is wall cling and wall jump
## (§7 movement requirements). The scrap curtain then rakes the face you are
## hanging on, so reaching a wall is not enough: you have to cross between
## them. Salvage Hook is the right reward because the power is the verb the
## fight spends three phases teaching (§12, §14).
##
## Design rules it obeys, same as the other three:
##   - every attack telegraphs for at least TELL_FLOOR seconds (§16), and the
##     tow's tell is the platform under your feet shaking before it goes
##   - never more than a readable number of projectiles alive at once
##   - each attack ends in a punish window reachable with the movement verbs
##     the game already taught (§33) — here that means coming back down for it
##   - three phases, each taking one more thing away rather than adding a number

signal defeated

enum State { INTRO, IDLE, TOW_TELL, TOW, SWEEP_TELL, SWEEP, RAKE_TELL, RAKE,
		WRECKED, DYING }

## No attack may become dangerous sooner than this after it starts telegraphing
## (§16). tools/check_bosses.py reads it and every tell timing below out of
## this file and fails if any tell is shorter.
const TELL_FLOOR := 0.5
## The arena talks to the fight through these two groups rather than through
## coordinates: what can be hauled away, and what is left to hang off. A room
## can be re-laid out without touching the boss (§29 data-driven resources),
## and — the reason it matters here — the fight cannot tow a surface the room
## did not offer, so the exit's ground can never be taken.
const TOWABLE_GROUP := "towable"
const WALL_GROUP := "tow_wall"

@export var scrap_scene: PackedScene
@export var arena_left: float = 130.0
@export var arena_right: float = 1470.0
## The wreck lane: the one line the rig runs on, and the line you cannot live on.
@export var lane_y: float = 548.0

# --- timings (seconds) ---
@export var idle_time: float = 0.85
@export var tow_tell: float = 0.95
@export var tow_time: float = 0.8
@export var sweep_tell: float = 0.8
@export var rake_tell: float = 0.75
@export var wrecked_time: float = 1.7

# --- attack values ---
@export var sweep_speed: float = 720.0
@export var haul_speed: float = 300.0
@export var hook_damage: int = 15
@export var hook_pull: float = 620.0
## How far above the lane the cable still finds you. Anything standing on the
## floor is inside it; anything clinging to a wall is not.
@export var hook_reach: float = 130.0
@export var scrap_damage: int = 12
@export var scrap_speed: float = 250.0
@export var scrap_gravity: float = 320.0
## Where a scrap curtain starts, and how far off the trailer's centre line it
## falls so that it rakes the face you cling to rather than the far side.
@export var rake_top_y: float = 120.0
@export var rake_face_offset: float = 34.0

@onready var visual: Node2D = $Visual
@onready var beacon: Polygon2D = $Visual/Beacon
@onready var boom: Node2D = $Boom
@onready var hook: Polygon2D = $Boom/Hook

var _state: int = State.INTRO
var _timer: float = 0.0
var _age: float = 0.0
var _player: Player = null
var _phase: int = 1
var _attack_index: int = 0
var _facing: int = -1
var _gravity: float = 1800.0
var _base_color: Color = Color(0.85, 0.82, 0.72)
var _tow_target: StaticBody2D = null
## The marked platform rattles around this, not around wherever it drifted to
## last frame, so the tell cannot walk a ledge out from under the player before
## the cable has actually taken it.
var _tow_base_x: float = 0.0
var _hauling: Array[StaticBody2D] = []
var _sweep_passes: int = 0
var _sweep_target: float = 0.0
var _boom_angle: float = -PI * 0.5


func _ready() -> void:
	always_active = true
	super._ready()
	var players := get_tree().get_nodes_in_group("player")
	if not players.is_empty():
		_player = players[0]
	_enter(State.INTRO, 1.2)
	Events.boss_spawned.emit("THE TOTAL LOSS", max_health)
	Events.boss_health_changed.emit(health, max_health)


func _physics_process(delta: float) -> void:
	_age += delta
	_timer -= delta
	_update_phase()
	_haul_platforms(delta)

	match _state:
		State.INTRO:
			_ride_lane(delta, 0.0)
			_aim_boom(delta, -PI * 0.5)
			if _timer <= 0.0:
				_enter(State.IDLE, idle_time)
		State.IDLE:
			# It rolls at you at walking pace. The lane is its yard and it never
			# leaves it, so idle is still pressure.
			_ride_lane(delta, 95.0)
			_face_player()
			_aim_boom(delta, -PI * 0.5)
			if _timer <= 0.0:
				_choose_attack()
		State.TOW_TELL:
			# The tell is the load, not the boss: the platform nearest you lights
			# up and rattles for the whole window before the cable takes it (§16).
			_ride_lane(delta, 0.0)
			_aim_boom(delta, _angle_to(_tow_target))
			_rattle_target()
			_flash(0.7)
			if _timer <= 0.0:
				_spring_hook()
		State.TOW:
			_ride_lane(delta, 0.0)
			_aim_boom(delta, _angle_to(_tow_target))
			if _timer <= 0.0:
				_stall()
				_enter(State.WRECKED, wrecked_time)
		State.SWEEP_TELL:
			_ride_lane(delta, 0.0)
			_face_player()
			_aim_boom(delta, 0.0)
			_flash(0.5)
			if _timer <= 0.0:
				_start_sweep()
		State.SWEEP:
			_run_sweep(delta)
			if _sweep_passes <= 0 or _timer <= 0.0:
				_stall()
				_enter(State.WRECKED, wrecked_time)
		State.RAKE_TELL:
			_ride_lane(delta, 0.0)
			_aim_boom(delta, -PI * 0.5)
			_flash(1.0)
			if _timer <= 0.0:
				_drop_rake()
		State.RAKE:
			_ride_lane(delta, 0.0)
			_aim_boom(delta, -PI * 0.5)
			if _timer <= 0.0:
				_stall()
				_enter(State.WRECKED, wrecked_time)
		State.WRECKED:
			# Punish window: the boom is out past its own footprint, so the rig
			# is down on its side in the lane — still, contact-safe, and worth
			# double. Reaching it means coming off the wall, which is the trade
			# the whole fight is built on (§33).
			velocity.x = move_toward(velocity.x, 0.0, 900.0 * delta)
			velocity.y += _gravity * delta
			move_and_slide()
			visual.rotation = sin(_age * 24.0) * 0.14
			_aim_boom(delta, -PI * 0.12)
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


## Sits on the lane and, with a roll speed, closes on the player along it.
func _ride_lane(delta: float, roll_speed: float) -> void:
	velocity = Vector2.ZERO
	global_position.y = move_toward(global_position.y, lane_y, 320.0 * delta)
	if roll_speed > 0.0 and is_instance_valid(_player):
		global_position.x = move_toward(global_position.x,
				_player.global_position.x, roll_speed * speed_factor * delta)
	global_position.x = clampf(global_position.x, arena_left, arena_right)


## The boom is a sibling of the body rather than a child of it, because the
## body flips with facing and a mirrored arm points at the wrong thing.
func _aim_boom(delta: float, target_angle: float) -> void:
	_boom_angle = lerp_angle(_boom_angle, target_angle, 1.0 - exp(-9.0 * delta))
	boom.rotation = _boom_angle
	hook.scale = Vector2.ONE * (1.0 + sin(_age * 12.0) * 0.09)


func _angle_to(node: Node2D) -> float:
	if not is_instance_valid(node):
		return -PI * 0.5
	return (node.global_position - global_position).angle()


func _face_player() -> void:
	if is_instance_valid(_player):
		_facing = 1 if _player.global_position.x > global_position.x else -1
	visual.scale.x = absf(visual.scale.x) * _facing


func _flash(rate_scale: float) -> void:
	var pulse := 0.5 + 0.5 * sin(_age * 30.0 * rate_scale)
	visual.modulate = _base_color.lerp(Color(2.2, 2.0, 1.4), pulse)
	beacon.color = Color(1.0, 0.72, 0.2).lerp(Color(1, 1, 1), pulse)


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
		_base_color = [Color(0.85, 0.82, 0.72), Color(0.95, 0.78, 0.5),
				Color(1.0, 0.62, 0.4)][phase - 1]


func _choose_attack() -> void:
	# Rotate rather than randomise, so the fight is learnable (§16).
	_attack_index += 1
	var pattern := [State.TOW_TELL, State.SWEEP_TELL, State.RAKE_TELL]
	if _phase == 2:
		# Two sweeps a lap: the ground it has not taken yet is still not yours.
		pattern = [State.TOW_TELL, State.SWEEP_TELL, State.RAKE_TELL,
				State.SWEEP_TELL]
	elif _phase >= 3:
		# By now there is nothing left to haul, so the tow comes for you, and
		# the rake — the only attack that reaches a wall — comes twice a lap.
		pattern = [State.SWEEP_TELL, State.RAKE_TELL, State.TOW_TELL,
				State.RAKE_TELL]
	var next: int = pattern[_attack_index % pattern.size()]
	# Phase speeds the tells up, but never below the telegraph floor: at phase
	# three a 0.5s tell scaled by 0.76 would be 0.38s, which is under the
	# reaction time the whole fight is designed around.
	var speed_scale := 1.0 - 0.12 * float(_phase - 1)
	match next:
		State.TOW_TELL:
			_mark_tow_target()
			_enter(State.TOW_TELL, maxf(tow_tell * speed_scale, TELL_FLOOR))
		State.SWEEP_TELL:
			_enter(State.SWEEP_TELL, maxf(sweep_tell * speed_scale, TELL_FLOOR))
		State.RAKE_TELL:
			_enter(State.RAKE_TELL, maxf(rake_tell * speed_scale, TELL_FLOOR))


## Every attack lands here: overbalanced, grounded, and safe to share a tile
## with. Nothing routes from one attack to the next (§16).
func _stall() -> void:
	Sfx.play("pound_impact", 0.06, 0.9)
	Juice.dust(global_position + Vector2(0.0, 44.0), 14)
	Juice.shake(9.0, 0.35)
	Juice.hit_stop(0.04)
	global_position.y = lane_y
	visual.rotation = 0.0
	_sweep_passes = 0


# --- the tow ----------------------------------------------------------------

## Marks the remaining platform nearest the player, so the fight always takes
## the ledge you were actually using rather than the one you had written off.
func _mark_tow_target() -> void:
	_tow_target = null
	var anchor := global_position.x
	if is_instance_valid(_player):
		anchor = _player.global_position.x
	var best := INF
	for node in get_tree().get_nodes_in_group(TOWABLE_GROUP):
		var platform := node as StaticBody2D
		if platform == null or _hauling.has(platform):
			continue
		var distance := absf(platform.global_position.x - anchor)
		if distance < best:
			best = distance
			_tow_target = platform
			_tow_base_x = platform.position.x


func _rattle_target() -> void:
	if not is_instance_valid(_tow_target):
		return
	_tow_target.position.x = _tow_base_x + sin(_age * 60.0) * 3.0
	_tow_target.modulate = Color(1.0, 0.86, 0.45).lerp(
			Color(2.0, 1.7, 0.7), 0.5 + 0.5 * sin(_age * 34.0))


func _spring_hook() -> void:
	if is_instance_valid(_tow_target):
		_haul(_tow_target)
	else:
		_snatch()
	_tow_target = null
	_enter(State.TOW, tow_time)


## Taking a platform is permanent — nothing in this fight gives ground back.
## That is the whole difference between this arena and the High-Water Mark's
## tide, and it is why the walls have to become home (§17).
func _haul(platform: StaticBody2D) -> void:
	platform.position.x = _tow_base_x
	platform.remove_from_group(TOWABLE_GROUP)
	# Off the world layer the instant the cable takes it: a surface that still
	# holds you up while it is visibly being dragged away is a lie.
	platform.collision_layer = 0
	platform.modulate = Color(1.0, 0.9, 0.65)
	_hauling.append(platform)
	Sfx.play("crate_break", 0.08, 0.9)
	Juice.shake(10.0, 0.4)
	Juice.dust(platform.global_position, 16)


func _haul_platforms(delta: float) -> void:
	for platform in _hauling.duplicate():
		if not is_instance_valid(platform):
			_hauling.erase(platform)
			continue
		var drift := signf(global_position.x - platform.global_position.x)
		platform.global_position += Vector2(drift * haul_speed * 0.3,
				-haul_speed) * delta
		platform.modulate.a = maxf(platform.modulate.a - delta * 0.4, 0.0)
		# Up onto the overpass deck and gone. Freed rather than parked off-screen
		# so a long fight does not accumulate invisible nodes (§30).
		if platform.global_position.y < -340.0:
			_hauling.erase(platform)
			platform.queue_free()


## When the yard is empty the cable comes for you instead. It sweeps the lane at
## standing height, so the answer is to not be standing: a wall is the one place
## in the arena the hook does not reach (§7 wall interaction).
func _snatch() -> void:
	Sfx.play("dash", 0.05, 0.8)
	Juice.shake(8.0, 0.3)
	if not is_instance_valid(_player):
		return
	if _player.global_position.y < lane_y - hook_reach:
		return
	if _player.is_on_wall():
		return
	_player.hurt(hook_damage, "written off by the Total Loss")
	# Set after hurt() so the drag reads even through i-frames: being shoved
	# down the lane is the hook working, not a second hit.
	_player.velocity = Vector2(
			signf(global_position.x - _player.global_position.x) * hook_pull, -140.0)


# --- the lane ---------------------------------------------------------------

func _start_sweep() -> void:
	global_position.y = lane_y
	_sweep_passes = 1 if _phase == 1 else 2
	# Always run to the far edge rather than the way it happens to be looking.
	# Started from a corner, "toward the player" can be a two-metre nudge, and a
	# sweep that does not cross the lane teaches the wrong lesson about the lane.
	_sweep_target = arena_left
	if absf(global_position.x - arena_right) > absf(global_position.x - arena_left):
		_sweep_target = arena_right
	_facing = 1 if _sweep_target > global_position.x else -1
	visual.scale.x = absf(visual.scale.x) * _facing
	Sfx.play("dash", 0.05, 0.9)
	Juice.shake(5.0, 0.25)
	_enter(State.SWEEP, 5.0)


## Driven by position rather than move_and_slide: the lane runs under the hung
## trailers, and a physics body would snag on them instead of passing beneath.
## The sweep has to own the entire floor or the walls mean nothing.
func _run_sweep(delta: float) -> void:
	velocity = Vector2.ZERO
	global_position.y = lane_y
	var step := sweep_speed * (1.0 + 0.12 * float(_phase - 1)) * speed_factor * delta
	global_position.x = move_toward(global_position.x, _sweep_target, step)
	visual.rotation = sin(_age * 40.0) * 0.05
	if absf(global_position.x - _sweep_target) > 1.0:
		return
	_sweep_passes -= 1
	Juice.dust(global_position + Vector2(0.0, 44.0), 12)
	Juice.shake(6.0, 0.2)
	_sweep_target = arena_right if _sweep_target <= arena_left + 1.0 else arena_left
	_facing = 1 if _sweep_target > global_position.x else -1
	visual.scale.x = absf(visual.scale.x) * _facing


## RAKE: a curtain of scrap down the face of the trailer you are nearest. It is
## the one attack that reaches a wall, and the answer is the gap between them —
## one wall jump crosses it (§7).
func _drop_rake() -> void:
	var walls := get_tree().get_nodes_in_group(WALL_GROUP)
	var target := _nearest_wall(walls)
	if scrap_scene == null or target == null:
		_stall()
		_enter(State.WRECKED, wrecked_time)
		return
	var centre := 0.0
	for node in walls:
		centre += (node as Node2D).global_position.x
	centre /= float(walls.size())
	# The clingable face is the one looking into the gap, so that is the side
	# the scrap comes down.
	var face_x := target.global_position.x + signf(
			centre - target.global_position.x) * rake_face_offset
	var count := 2 + _phase
	var parent := get_parent()
	for i in count:
		var scrap: Node2D = scrap_scene.instantiate()
		parent.add_child(scrap)
		scrap.launch(Vector2(face_x, rake_top_y - float(i) * 80.0),
				Vector2(0.0, scrap_speed), scrap_damage, scrap_gravity)
	Sfx.play("crate_break", 0.1, 0.85)
	Juice.shake(6.0, 0.25)
	_enter(State.RAKE, 0.7)


func _nearest_wall(walls: Array) -> Node2D:
	var anchor := global_position.x
	if is_instance_valid(_player):
		anchor = _player.global_position.x
	var best := INF
	var found: Node2D = null
	for node in walls:
		var wall := node as Node2D
		if wall == null:
			continue
		var distance := absf(wall.global_position.x - anchor)
		if distance < best:
			best = distance
			found = wall
	return found


# --- damage -----------------------------------------------------------------

func _on_hitbox_body_entered(body: Node2D) -> void:
	# Contact only hurts while it is working. The punish window is safe to be
	# inside, which is what makes it a window rather than a bluff.
	if _state in [State.WRECKED, State.INTRO, State.DYING]:
		return
	super._on_hitbox_body_entered(body)


func take_damage(amount: int) -> void:
	if _state == State.DYING:
		return
	# Wrecked means exposed: it is worth leaving the wall for.
	super.take_damage(amount * (2 if _state == State.WRECKED else 1))
	if health > 0:
		Events.boss_health_changed.emit(health, max_health)


func die() -> void:
	if _state == State.DYING:
		return
	_state = State.DYING
	_tow_target = null
	Events.boss_health_changed.emit(0, max_health)
	GameManager.record_enemy_defeated()
	GameManager.record_boss_defeated()
	# Absorbing the boss's power is the reward for the fight (§12). Salvage Hook
	# is its own cable, turned around: the rig spent the fight teaching you to
	# live on walls, and hands over the line that throws you at one.
	GameManager.grant_ability(Abilities.SALVAGE_HOOK)
	Sfx.play("room_clear")
	Juice.shake(14.0, 0.9)
	Juice.hit_stop(0.12)
	Juice.enemy_death(global_position, Color(0.95, 0.7, 0.3))
	_drop_premiums()
	defeated.emit()
	queue_free()
