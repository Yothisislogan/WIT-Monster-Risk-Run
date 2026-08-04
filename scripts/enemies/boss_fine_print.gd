extends EnemyBase
## THE FINE PRINT — the contract vault under WIT Headquarters (GAME_DESIGN.md
## §12, §16, §18).
##
## The fourth fight, and deliberately the fourth *shape*. The Inferno Adjuster
## is a body you stomp. The Actuary never lands, and asks where you are in the
## air. The High-Water Mark attacks the floor, and asks how much ground is
## left. This one is never in reach at all: it is bolted to the vault gantry,
## clear of the double-jump budget in the header of scripts/player/player.gd,
## and it stays there for the whole fight.
##
## What you fight are the RIDERS it lowers onto the plinths (see
## scripts/enemies/fine_print_rider.gd): armoured clauses that every gun in the
## game rings off. A seal opens to a ground pound passing through it and to
## nothing else, and once open only Monster Munch takes it off the board (§7).
## Voiding a rider snaps its chain taut and hauls the Fine Print down over that
## plinth — SAGGING, the only state in which it can be hurt at all, and so the
## only reason its health bar ever moves.
##
## That is the whole design: you cannot shoot your way through this one, and
## running away only lets the arena finish shrinking. It hands over CLAUSE
## BREAKER, which is the same pound turned around and startable from standing
## (§12) — the fight teaches the verb before it gives you the power.
##
## Design rules it obeys, same as the other three:
##   - every attack telegraphs for at least TELL_FLOOR seconds before it can
##     hurt you (§16). Here the tells are positional — the arena is what is
##     under attack, so what has to be readable is *where*
##   - every attack ends in a punish window, but the one a voided rider buys is
##     four times the one the boss gives away for free
##   - three phases, each adding an idea rather than a bigger number
##   - hazards are areas, never geometry. Nothing here disables a platform:
##     tools/check_reachability.py proves this arena is traversable by reading
##     the scene, and a boss that deleted a plinth at runtime would quietly
##     make that proof a lie

signal defeated

enum State { INTRO, IDLE, RIDER_TELL, RIDER, EXCLUSION_TELL, EXCLUSION,
		SWEEP_TELL, SWEEP, SAGGING, DYING }

## No attack may become dangerous sooner than this after it starts telegraphing
## (§16). tools/check_bosses.py reads it and every tell timing below out of this
## file, and fails if any tell is shorter — before or after the phase speed-up.
const TELL_FLOOR := 0.5

# --- the arena (mirrors scenes/rooms/boss_fine_print.tscn) -------------------
@export var arena_left: float = 200.0
@export var arena_right: float = 1400.0
## The gantry it hangs from. The plinth tops are at y 484, so a double jump
## from the best standing spot in the room reaches y 213 at the very top of the
## arc: this is 117px above that, and out of reach on purpose.
@export var ceiling_y: float = 36.0
@export var bolt_y: float = 96.0
## Where the slack chain drops it: resting on the plinth tops, which is exactly
## where the player is standing at the moment they Munch a rider.
@export var sag_y: float = 448.0
@export var plinth_top_y: float = 484.0
@export var plinth_x: Array[float] = [250.0, 650.0, 1050.0, 1450.0]
## Half the rider's height, so a lowered clause seats on the plinth surface
## instead of sinking into it.
@export var rider_seat_offset: float = 28.0
@export var rail_speed: float = 520.0
@export var retract_speed: float = 640.0

# --- timings (seconds) ------------------------------------------------------
@export var idle_time: float = 0.8
## The rail slide is the tell: it commits to a plinth before anything descends,
## so you know which one is about to cost you.
@export var rider_tell: float = 0.9
## How long a clause takes to come down. It is harmless the whole way.
@export var rider_time: float = 1.1
@export var exclusion_tell: float = 0.8
@export var exclusion_time: float = 2.8
@export var sweep_tell: float = 0.7
@export var sweep_time: float = 2.6
## The window a voided clause buys you...
@export var void_sag: float = 2.4
## ...and the dip it cannot help giving away every time it reels a chain back
## in. Long enough for one committed hit, nowhere near enough to win on.
@export var slack_sag: float = 0.6
## How long a sealed clause waits before it ratifies, at phase one.
@export var ratify_time: float = 5.5

# --- attack values ----------------------------------------------------------
@export var exclusion_damage: int = 14
## Voided floor, widening per phase. Even at the widest there is standing room
## either side of it, because the answer is meant to be a plinth and not a
## coin flip.
@export var exclusion_widths: Array[float] = [340.0, 460.0, 580.0]
@export var sweep_damage: int = 16
@export var sweep_speed: float = 700.0
## Head height for someone standing on a plinth, and clear over someone on the
## floor: the sweep says "get down" as plainly as the exclusion says "get up".
@export var sweep_y: float = 440.0
@export var hazard_tick: float = 0.45

@onready var visual: Node2D = $Visual
@onready var chain_rig: Node2D = $Visual/ChainRig
@onready var wax: Polygon2D = $Visual/Wax
@onready var exclusion: Node2D = $Exclusion
@onready var exclusion_band: Polygon2D = $Exclusion/Band
@onready var exclusion_area: Area2D = $Exclusion/BandArea
@onready var sweep: Node2D = $Sweep
@onready var sweep_flail: Polygon2D = $Sweep/Flail
@onready var sweep_area: Area2D = $Sweep/FlailArea
@onready var _riders: Array[Node] = [$Riders/RiderA, $Riders/RiderB, $Riders/RiderC]

var _state: int = State.INTRO
var _timer: float = 0.0
var _age: float = 0.0
var _player: Player = null
var _phase: int = 1
var _attack_index: int = 0
var _base_color: Color = Color(0.78, 0.72, 0.56)
## Where the rail is taking it. It always hangs over whatever it is doing, so
## its position is a second read on the attack.
var _target_x: float = 800.0
var _sweep_direction: float = 1.0
var _sweep_passes: int = 0
var _hazard_tick: float = 0.0


func _ready() -> void:
	always_active = true
	super._ready()
	var players := get_tree().get_nodes_in_group("player")
	if not players.is_empty():
		_player = players[0]
	for rider in _riders:
		rider.cracked.connect(_on_rider_cracked)
		rider.ratified.connect(_on_rider_ratified)
		rider.voided.connect(_on_rider_voided)
	_close_exclusion()
	_close_sweep()
	global_position = Vector2(clampf(global_position.x, arena_left, arena_right), bolt_y)
	_target_x = global_position.x
	_enter(State.INTRO, 1.3)
	Events.boss_spawned.emit("THE FINE PRINT", max_health)
	Events.boss_health_changed.emit(health, max_health)


func _physics_process(delta: float) -> void:
	_age += delta
	_timer -= delta
	_hazard_tick = maxf(_hazard_tick - delta, 0.0)
	_update_phase()

	match _state:
		State.INTRO:
			_ride_rail(_player_x(), delta)
			if _timer <= 0.0:
				_enter(State.IDLE, idle_time)
		State.IDLE:
			_ride_rail(_player_x(), delta)
			if _timer <= 0.0:
				_choose_attack()
		State.RIDER_TELL:
			_ride_rail(_target_x, delta)
			_flash(0.8)
			if _timer <= 0.0:
				_lower_riders()
		State.RIDER:
			_ride_rail(_target_x, delta)
			if _timer <= 0.0:
				_reel(global_position.x)
				_enter(State.SAGGING, slack_sag)
		State.EXCLUSION_TELL:
			# The band is a stencil held under the body: it tracks the body,
			# the body tracks you, and it locks where it lands when the tell
			# runs out. Outrunning it is not the answer; the plinths are.
			_ride_rail(_player_x(), delta)
			_aim_exclusion(delta)
			_flash(1.0)
			if _timer <= 0.0:
				_open_exclusion()
		State.EXCLUSION:
			_ride_rail(_player_x(), delta)
			_hurt_in(exclusion_area, exclusion_damage, "excluded by the Fine Print")
			if _timer <= 0.0:
				_close_exclusion()
				_reel(global_position.x)
				_enter(State.SAGGING, slack_sag)
		State.SWEEP_TELL:
			_ride_rail(sweep.position.x, delta)
			_flash(0.6)
			if _timer <= 0.0:
				_open_sweep()
		State.SWEEP:
			_ride_rail(sweep.position.x, delta)
			_move_sweep(delta)
			_hurt_in(sweep_area, sweep_damage, "struck out by the Fine Print")
			if _sweep_passes <= 0 or _timer <= 0.0:
				_close_sweep()
				_reel(global_position.x)
				_enter(State.SAGGING, slack_sag)
		State.SAGGING:
			# Punish window: hauled down to plinth height by its own chain,
			# contact-safe, taking double, and open only here.
			_hang_slack(delta)
			if _timer < 0.35:
				_flash(1.4)     # the plating closing again is its own tell
			if _timer <= 0.0:
				visual.rotation = 0.0
				_enter(State.IDLE, idle_time)
		State.DYING:
			_hang_slack(delta)


# --- state helpers ----------------------------------------------------------

func _enter(state: int, timer: float) -> void:
	_state = state
	_timer = timer
	visual.modulate = Color.WHITE


## It never leaves the gantry. The only vertical move it makes all fight is the
## sag, and the retract that closes it.
func _ride_rail(target_x: float, delta: float) -> void:
	global_position.x = move_toward(global_position.x,
			clampf(target_x, arena_left, arena_right), rail_speed * delta)
	global_position.y = move_toward(global_position.y, bolt_y, retract_speed * delta)
	velocity = Vector2.ZERO
	_update_chain()


## Slack, and swinging along the rail toward whatever is still pulling on it.
## That is also what stops the free window being a bluff at the far wall: the
## sweep can end anywhere in the room, and a punish window you cannot cross the
## arena to reach in 0.6s is not one (§16).
func _hang_slack(delta: float) -> void:
	global_position.x = move_toward(global_position.x,
			clampf(_player_x(), arena_left, arena_right), rail_speed * delta)
	global_position.y = sag_y + sin(_age * 7.0) * 5.0
	visual.rotation = sin(_age * 16.0) * 0.07
	velocity = Vector2.ZERO
	_update_chain()


## The chain always reaches the gantry, whatever height the body is at. It is
## the only thing on screen that says "this is held up by something", which is
## the whole reason the punish window reads as a mistake it made.
func _update_chain() -> void:
	chain_rig.scale.y = maxf((global_position.y - ceiling_y) * 0.01, 0.1)


func _flash(rate_scale: float) -> void:
	var pulse := 0.5 + 0.5 * sin(_age * 30.0 * rate_scale)
	visual.modulate = _base_color.lerp(Color(2.2, 2.1, 1.7), pulse)
	wax.color = Color(0.86, 0.24, 0.28).lerp(Color(1, 1, 1), pulse)


func _player_x() -> float:
	if is_instance_valid(_player):
		return _player.global_position.x
	return 0.5 * (arena_left + arena_right)


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
		_base_color = [Color(0.78, 0.72, 0.56), Color(0.72, 0.62, 0.44),
				Color(0.66, 0.50, 0.34)][phase - 1]
		# The vault reprints and every clause on the board lapses, ratified or
		# not. Each phase hands the arena back and then asks for it again (§16),
		# which is what keeps a bad phase from compounding into an unwinnable
		# one.
		for rider in _riders:
			rider.recall()


func _choose_attack() -> void:
	# Rotate rather than randomise, so the fight is learnable (§16). Riders are
	# half of every rotation because they are the fight; the other two attacks
	# exist to make servicing one expensive.
	_attack_index += 1
	var pattern := [State.RIDER_TELL, State.EXCLUSION_TELL,
			State.RIDER_TELL, State.SWEEP_TELL]
	if _phase >= 2:
		pattern = [State.RIDER_TELL, State.SWEEP_TELL, State.RIDER_TELL,
				State.EXCLUSION_TELL, State.SWEEP_TELL]
	var next: int = pattern[_attack_index % pattern.size()]
	var plinth := _free_plinth()
	if next == State.RIDER_TELL and (plinth < 0 or _dormant_rider() == null):
		next = State.EXCLUSION_TELL     # nothing left to sign; lean on the floor
	# Phase speeds the tells up, but never below the telegraph floor: at phase
	# three a 0.7s tell scaled by 0.76 is 0.53s, and one more phase of the same
	# slope would put it under the reaction time the fight is designed around.
	var speed_scale := 1.0 - 0.12 * float(_phase - 1)
	match next:
		State.RIDER_TELL:
			_target_x = plinth_x[plinth]
			_enter(State.RIDER_TELL, maxf(rider_tell * speed_scale, TELL_FLOOR))
		State.EXCLUSION_TELL:
			_paint_exclusion()
			_enter(State.EXCLUSION_TELL, maxf(exclusion_tell * speed_scale, TELL_FLOOR))
		State.SWEEP_TELL:
			_paint_sweep()
			_enter(State.SWEEP_TELL, maxf(sweep_tell * speed_scale, TELL_FLOOR))


## The chain gives way all at once rather than lowering it politely: a window
## that spends a third of itself arriving is a third of a window.
func _reel(at_x: float) -> void:
	global_position = Vector2(clampf(at_x, arena_left, arena_right), sag_y)
	Sfx.play("pound_impact", 0.08, 0.9)
	Juice.dust(global_position + Vector2(0.0, 42.0), 10)
	_update_chain()


# --- riders -----------------------------------------------------------------

func _dormant_rider() -> Node:
	for rider in _riders:
		if rider.is_dormant():
			return rider
	return null


## The plinth nearest the player, so a clause lands on the ground you were
## actually using. Returns -1 when only one plinth is left free: the Fine Print
## never signs the last one, because an arena with no refuge in it is not a
## fight (§16). Three riders over four plinths makes that true by construction;
## the guard says so out loud so a fourth rider cannot quietly break it.
func _free_plinth() -> int:
	var taken: Array[int] = []
	for rider in _riders:
		if not rider.is_dormant():
			taken.append(rider.claimed_plinth())
	if taken.size() >= plinth_x.size() - 1:
		return -1
	var best := -1
	var best_distance := 0.0
	for i in plinth_x.size():
		if i in taken:
			continue
		var distance: float = absf(plinth_x[i] - _player_x())
		if best < 0 or distance < best_distance:
			best = i
			best_distance = distance
	return best


## Phase decides how many clauses come down at once and how long their fuses
## are. Nothing about a single rider gets harder — there are just more of them
## to service in less time, which is pressure on the verb rather than on your
## Coverage bar.
func _lower_riders() -> void:
	var lowered := 0
	for _wave in _phase:
		var plinth := _free_plinth()
		var rider: Node = _dormant_rider()
		if plinth < 0 or rider == null:
			break
		rider.deploy(plinth, Vector2(plinth_x[plinth], ceiling_y),
				Vector2(plinth_x[plinth], plinth_top_y - rider_seat_offset),
				rider_time, ratify_time * (1.0 - 0.15 * float(_phase - 1)))
		lowered += 1
	if lowered == 0:
		_reel(global_position.x)
		_enter(State.SAGGING, slack_sag)
		return
	Sfx.play("charged_shot", 0.06, 0.75)
	Juice.shake(4.0, 0.25)
	_enter(State.RIDER, rider_time)


func _on_rider_cracked(_plinth_index: int) -> void:
	# It flinches when a seal goes, which is the only encouragement the player
	# gets that the pound was the right idea.
	Juice.shake(5.0, 0.25)
	Sfx.play_pitched("enemy_hit", 5.0)


func _on_rider_ratified(_plinth_index: int) -> void:
	Juice.shake(6.0, 0.35)
	Sfx.play("charge_ready", 0.05, 0.7)


## The fight, in one function. A voided clause snaps its chain taut, drags the
## Fine Print down over that plinth, and cancels whatever it was in the middle
## of: the reward for the two verbs is defensive as well as offensive (§14).
func _on_rider_voided(plinth_index: int) -> void:
	if _state == State.DYING or _state == State.INTRO:
		return
	_close_exclusion()
	_close_sweep()
	_reel(plinth_x[clampi(plinth_index, 0, plinth_x.size() - 1)])
	Juice.shake(11.0, 0.5)
	Sfx.play("land_hard", 0.05)
	_enter(State.SAGGING, void_sag)


# --- the exclusion ----------------------------------------------------------

## A band of floor struck out of the contract. One node carries the paint and
## the hurt area together, so what you can see and what can hurt you cannot
## disagree — the same rule the High-Water Mark's tide follows.
func _paint_exclusion() -> void:
	var width: float = exclusion_widths[mini(_phase - 1, exclusion_widths.size() - 1)]
	exclusion.scale.x = width * 0.01
	exclusion.position.x = global_position.x
	exclusion_band.color = Color(0.12, 0.10, 0.14, 0.35)
	exclusion.show()
	exclusion_area.set_deferred("monitoring", false)


func _aim_exclusion(delta: float) -> void:
	exclusion.position.x = move_toward(
			exclusion.position.x, global_position.x, 600.0 * delta)
	var beat := 0.5 + 0.5 * sin(_age * 26.0)
	exclusion_band.color = Color(0.12, 0.10, 0.14, 0.25 + 0.25 * beat)


func _open_exclusion() -> void:
	exclusion_band.color = Color(0.06, 0.05, 0.08, 0.92)
	exclusion_area.set_deferred("monitoring", true)
	Sfx.play("low_coverage", 0.05, 0.8)
	Juice.shake(6.0, 0.3)
	_enter(State.EXCLUSION, exclusion_time)


func _close_exclusion() -> void:
	exclusion.hide()
	exclusion_area.set_deferred("monitoring", false)


# --- the indemnity sweep ----------------------------------------------------

## A chain flail at plinth-head height. It starts from the wall the player is
## furthest from, so it always arrives across open ground rather than out of
## the wall behind you.
func _paint_sweep() -> void:
	var from_left := _player_x() > 0.5 * (arena_left + arena_right)
	_sweep_direction = 1.0 if from_left else -1.0
	_sweep_passes = _phase
	sweep.position = Vector2(arena_left if from_left else arena_right, sweep_y)
	sweep_flail.color = Color(0.62, 0.58, 0.46, 0.45)
	sweep.show()
	sweep_area.set_deferred("monitoring", false)


func _open_sweep() -> void:
	sweep_flail.color = Color(0.86, 0.80, 0.62, 1.0)
	sweep_area.set_deferred("monitoring", true)
	Sfx.play("dash", 0.05, 0.9)
	_enter(State.SWEEP, sweep_time * float(maxi(_sweep_passes, 1)))


## Later phases send it back rather than making it faster: a second pass asks
## the same question again while you are still recovering from your answer.
func _move_sweep(delta: float) -> void:
	sweep.position.x += _sweep_direction * sweep_speed * delta
	sweep_flail.rotation += 12.0 * delta
	if sweep.position.x <= arena_left or sweep.position.x >= arena_right:
		sweep.position.x = clampf(sweep.position.x, arena_left, arena_right)
		_sweep_direction = -_sweep_direction
		_sweep_passes -= 1
		Juice.dust(sweep.position, 6)


func _close_sweep() -> void:
	sweep.hide()
	sweep_flail.rotation = 0.0
	sweep_area.set_deferred("monitoring", false)


# --- hazards ----------------------------------------------------------------

## Hazards cost Coverage on a tick rather than continuously, so clipping the
## corner of one is a price and not a death sentence (§16). It matters more
## here than usual: Player.hurt cancels a pound, so one tick is what makes
## cracking a seal from inside an exclusion a bad idea rather than an
## impossible one.
func _hurt_in(area: Area2D, damage: int, source: String) -> void:
	if _hazard_tick > 0.0 or not area.monitoring:
		return
	for body in area.get_overlapping_bodies():
		if body is Player:
			body.hurt(damage, source)
			_hazard_tick = hazard_tick
			return


# --- damage -----------------------------------------------------------------

func _on_hitbox_body_entered(body: Node2D) -> void:
	# Contact only hurts while it is working. The punish window is safe to be
	# inside, which is what makes it a window rather than a bluff.
	if _state in [State.SAGGING, State.INTRO, State.DYING]:
		return
	super._on_hitbox_body_entered(body)


func take_damage(amount: int) -> void:
	if _state == State.DYING:
		return
	# Bolted plating: while it is up there the whole arsenal rings off it, the
	# same way it rings off a rider. The riders are the fight, not the ceiling.
	if _state != State.SAGGING:
		Sfx.play("enemy_hit", 0.2, 0.4)
		Juice.hit_spark(global_position)
		return
	# Sagging means torn open, and the multiplier is written in the literal form
	# tools/check_bosses.py reads so the contract is checked and not just meant.
	super.take_damage(amount * (2 if _state == State.SAGGING else 1))
	if health > 0:
		Events.boss_health_changed.emit(health, max_health)


func die() -> void:
	if _state == State.DYING:
		return
	_state = State.DYING
	_close_exclusion()
	_close_sweep()
	for rider in _riders:
		rider.recall()
	Events.boss_health_changed.emit(0, max_health)
	GameManager.record_enemy_defeated()
	GameManager.record_boss_defeated()
	# Absorbing the boss's power is the reward for the fight (§12). Clause
	# Breaker is this fight's own verb handed back: the pound that opened its
	# riders, now startable from standing, against everyone else's armour.
	GameManager.grant_ability(Abilities.CLAUSE_BREAKER)
	Sfx.play("room_clear")
	Juice.shake(14.0, 0.9)
	Juice.hit_stop(0.12)
	Juice.enemy_death(global_position, Color(0.92, 0.86, 0.62))
	_drop_premiums()
	defeated.emit()
	queue_free()
