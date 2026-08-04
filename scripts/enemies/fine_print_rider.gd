extends StaticBody2D
## A RIDER of THE FINE PRINT: one armoured clause, bolted onto an arena plinth
## by the boss on the ceiling (GAME_DESIGN.md §7, §12, §16).
##
## Deliberately *not* an EnemyBase. An EnemyBase has health, and health is the
## one thing a rider must not have: the fight's whole question is "which verb
## opens this", and anything with health is always answered by shooting it.
## So every weapon in the game rings off the plate, the seal opens to a ground
## pound passing through it and to nothing else, and once open only Monster
## Munch takes it off the board (§7). Two verbs, in order, or nothing happens.
##
## Fail to void it in time and it RATIFIES: the clause becomes final for the
## rest of the phase and its plinth turns from a refuge into a hazard. That is
## how the Fine Print deletes the arena you were standing on, and why the fight
## is a race rather than a damage check.

## Carries the plinth index so the boss knows which chain went slack and where
## to sag; see scripts/enemies/boss_fine_print.gd.
signal cracked(plinth_index: int)
signal ratified(plinth_index: int)
signal voided(plinth_index: int)

enum RiderState { DORMANT, LOWERING, SEALED, CRACKED, RATIFIED }

## Touching a live clause costs Coverage on a tick rather than continuously,
## the same bargain the High-Water Mark's tide makes: brushing one is a price,
## not a death sentence (§16).
@export var contact_damage: int = 12
@export var ratified_damage: int = 18
@export var hurt_tick: float = 0.5
## How long the seal stays open once a pound cracks it. This is the Munch
## window, and it is short on purpose — cracking is not the reward, eating is.
@export var crack_window: float = 2.4
## What a re-sealed clause gives you back. Missing the Munch costs you the fuse
## you had left, but never leaves you with a rider that ratifies instantly.
@export var reseal_grace: float = 1.2
@export var currency_reward: int = 12

@onready var visual: Node2D = $Visual
@onready var plate: Polygon2D = $Visual/Plate
@onready var wax: Polygon2D = $Visual/Wax
@onready var seal_area: Area2D = $SealArea

## Which plinth this rider is bolted to, or -1 while dormant.
var plinth: int = -1

var _state: int = RiderState.DORMANT
var _timer: float = 0.0
var _fuse: float = 0.0
var _lower_time: float = 1.0
var _age: float = 0.0
var _tick: float = 0.0
var _anchor: Vector2 = Vector2.ZERO
var _from: Vector2 = Vector2.ZERO


func _ready() -> void:
	_go_dormant()


func _physics_process(delta: float) -> void:
	_age += delta
	_tick = maxf(_tick - delta, 0.0)
	match _state:
		RiderState.LOWERING:
			# Harmless the whole way down: the descent is the telegraph, and a
			# telegraph that can hurt you is not one (§16).
			_timer -= delta
			var fell := 1.0 - clampf(_timer / maxf(_lower_time, 0.001), 0.0, 1.0)
			global_position = _from.lerp(_anchor, fell)
			if _timer <= 0.0:
				_seal(_fuse)
		RiderState.SEALED:
			_hold()
			_fuse -= delta
			# The crack is checked before the bite, so a pound is always the
			# safe answer and walking into one never is.
			if _pound_through_seal():
				_crack()
			elif _fuse <= 0.0:
				_ratify()
			else:
				_pulse(Color(0.95, 0.78, 0.30), 9.0)
				_bite(contact_damage, "signed by the fine print")
		RiderState.CRACKED:
			_hold()
			_timer -= delta
			_pulse(Color(0.55, 1.0, 0.60), 16.0)
			visual.rotation = sin(_age * 24.0) * 0.09
			if _timer <= 0.0:
				visual.rotation = 0.0
				_seal(maxf(_fuse, reseal_grace))
		RiderState.RATIFIED:
			_hold()
			_pulse(Color(0.98, 0.32, 0.36), 4.0)
			_bite(ratified_damage, "ratified by the fine print")


# --- the boss's handle on it ------------------------------------------------

func is_dormant() -> bool:
	return _state == RiderState.DORMANT


## Which plinth this clause is bolted to, or -1 while dormant. A method rather
## than a bare property read so the boss is never holding a copy of a number
## the rider owns.
func claimed_plinth() -> int:
	return plinth


## Lower a fresh clause onto `index`. `fuse` is how long the player has to
## crack it before it ratifies, which is the number the phases turn down.
func deploy(index: int, from: Vector2, to: Vector2, lower_time: float, fuse: float) -> void:
	plinth = index
	_from = from
	_anchor = to
	_lower_time = maxf(lower_time, 0.05)
	_timer = _lower_time
	_fuse = maxf(fuse, 1.0)
	_state = RiderState.LOWERING
	global_position = from
	visual.rotation = 0.0
	visual.scale = Vector2.ONE
	plate.color = Color(0.86, 0.80, 0.62)
	wax.color = Color(0.95, 0.78, 0.30)
	show()
	seal_area.set_deferred("monitoring", true)


## The vault reprints itself between phases and every clause on the board
## lapses, ratified or not: each phase hands the arena back and asks for it
## again (§16).
func recall() -> void:
	if _state == RiderState.DORMANT:
		return
	Juice.dust(global_position, 8)
	_go_dormant()


# --- the player's two verbs -------------------------------------------------

## Monster Munch is the only removal (§7), and that is what makes the fight
## sustainable rather than a war of attrition: GameManager.record_enemy_consumed
## heals and pays 25 ability energy, so the loop that opens the boss also feeds
## the Coverage and the meter the loop costs you.
##
## This deliberately does not chain to EnemyBase.consume(): a voided clause is
## not an enemy defeat, and the node is reused for the next one rather than
## freed.
func consume() -> void:
	GameManager.record_enemy_consumed()
	GameManager.add_currency(currency_reward)
	Sfx.play_chain("streak")
	Juice.enemy_death(global_position, Color(0.98, 0.88, 0.45))
	Juice.hit_stop(0.05)
	var index := plinth
	_go_dormant()
	voided.emit(index)


func can_be_munched() -> bool:
	return _state == RiderState.CRACKED


## Guns, charged shots, stomps and the pound's own shockwave all arrive here,
## and none of them open a clause plate. The deflect is loud because silence
## would read as a broken hitbox rather than as armour (§16).
func take_damage(_amount: int) -> void:
	if _state == RiderState.DORMANT or _state == RiderState.CRACKED:
		return
	Sfx.play("enemy_hit", 0.2, 0.45)
	Juice.hit_spark(global_position + Vector2(0.0, -26.0))


# --- internals --------------------------------------------------------------

## Reads the player's own pound state rather than a damage number, so CLAUSE
## BREAKER — the power this fight hands over, which is a pound started from
## standing — opens a seal exactly like the free one does (§12, §14).
func _pound_through_seal() -> bool:
	for body in seal_area.get_overlapping_bodies():
		if body is Player and body.pounding:
			return true
	return false


func _crack() -> void:
	_state = RiderState.CRACKED
	_timer = crack_window
	plate.color = Color(0.42, 0.62, 0.44)
	Sfx.play("crate_break", 0.1)
	Juice.shockwave(global_position)
	Juice.shake(7.0, 0.3)
	Juice.hit_stop(0.06)
	Juice.debris(global_position, Color(0.86, 0.80, 0.62))
	cracked.emit(plinth)


func _seal(fuse: float) -> void:
	_state = RiderState.SEALED
	_fuse = fuse
	plate.color = Color(0.86, 0.80, 0.62)
	visual.scale = Vector2.ONE


func _ratify() -> void:
	_state = RiderState.RATIFIED
	plate.color = Color(0.34, 0.10, 0.16)
	visual.scale = Vector2(1.18, 1.14)
	Sfx.play("charge_ready", 0.05, 0.8)
	Juice.shake(5.0, 0.3)
	ratified.emit(plinth)


func _go_dormant() -> void:
	_state = RiderState.DORMANT
	plinth = -1
	visual.rotation = 0.0
	visual.scale = Vector2.ONE
	hide()
	seal_area.set_deferred("monitoring", false)
	# Parked off the arena rather than left invisible on its plinth: a hidden
	# body still stops bullets, which would read as a ghost wall.
	global_position = Vector2(-400.0, -400.0)


## Bolted. Re-asserting the anchor every frame is what makes that true against
## Undertow, which drags anything with take_damage() toward the player.
func _hold() -> void:
	global_position = _anchor


func _bite(damage: int, source: String) -> void:
	if _tick > 0.0:
		return
	for body in seal_area.get_overlapping_bodies():
		if body is Player:
			body.hurt(damage, source)
			_tick = hurt_tick
			return


func _pulse(tint: Color, rate: float) -> void:
	var beat := 0.5 + 0.5 * sin(_age * rate)
	wax.color = tint.lerp(Color(1, 1, 1), beat * 0.7)
