class_name EnemyBase
extends CharacterBody2D
## Reusable enemy foundation (GAME_DESIGN.md §16, §29): health, contact
## damage, defeat rewards, and off-screen processing pause (§30).

@export var max_health: int = 30
@export var contact_damage: int = 10
@export var currency_reward: int = 5
@export var defeat_source: String = "unknown enemy"
## Below this health fraction the enemy is weakened and can be Munched (§7).
@export var weaken_ratio: float = 0.4
## Premiums scattered on defeat. Falls back to silent currency if unset.
@export var premium_scene: PackedScene
@export var premium_drops: int = 2
@export var death_color: Color = Color(1.0, 0.55, 0.25)
## Bosses and scripted enemies opt out of the off-screen processing pause.
@export var always_active: bool = false

var health: int
var weakened: bool = false
var burn_ticks: int = 0
var burn_damage: int = 0

@onready var hitbox: Area2D = $Hitbox
@onready var visibility_notifier: VisibleOnScreenNotifier2D = $OnScreen

var _burn_timer: Timer
var _health_fill: Polygon2D
var _health_bg: Polygon2D
var is_elite: bool = false


func _ready() -> void:
	add_to_group("enemies")
	# Perils scale with the Risk Meter (§11), applied once at spawn.
	max_health = maxi(int(round(float(max_health) * GameManager.enemy_health_factor())), 1)
	_maybe_promote_to_elite()
	health = max_health
	hitbox.body_entered.connect(_on_hitbox_body_entered)
	if always_active:
		set_physics_process(true)
	else:
		# Pause processing while off screen (§30).
		visibility_notifier.screen_entered.connect(func() -> void: set_physics_process(true))
		visibility_notifier.screen_exited.connect(func() -> void: set_physics_process(false))
		set_physics_process(false)
	_burn_timer = Timer.new()
	_burn_timer.wait_time = 0.5
	_burn_timer.timeout.connect(_on_burn_tick)
	add_child(_burn_timer)
	_build_health_bar()


## At high Risk a share of perils arrive as elites: visibly larger, tougher,
## and worth more. This is the Risk Meter you can actually see (§11).
func _maybe_promote_to_elite() -> void:
	if always_active or GameManager.risk < 0.35:
		return
	var chance := (GameManager.risk - 0.35) * 0.55
	if randf() > chance:
		return
	is_elite = true
	max_health = int(round(float(max_health) * 1.8))
	contact_damage = int(round(float(contact_damage) * 1.35))
	currency_reward = int(round(float(currency_reward) * 2.0))
	premium_drops += 2
	defeat_source = "outmatched by an elite peril"
	scale = Vector2(1.28, 1.28)
	modulate = Color(1.25, 0.9, 1.15)


## A hairline bar that only appears once the enemy has been hurt, so a full
## screen of untouched enemies stays uncluttered on a phone (§16, §23).
func _build_health_bar() -> void:
	_health_bg = Polygon2D.new()
	_health_bg.polygon = PackedVector2Array([
		Vector2(-20, -34), Vector2(20, -34), Vector2(20, -29), Vector2(-20, -29)])
	_health_bg.color = Color(0.05, 0.05, 0.08, 0.75)
	_health_bg.visible = false
	add_child(_health_bg)

	_health_fill = Polygon2D.new()
	_health_fill.polygon = PackedVector2Array([
		Vector2(0, -34), Vector2(40, -34), Vector2(40, -29), Vector2(0, -29)])
	_health_fill.position = Vector2(-20, 0)
	_health_fill.color = Color(0.95, 0.35, 0.3)
	_health_fill.visible = false
	add_child(_health_fill)


func _refresh_health_bar() -> void:
	if _health_fill == null:
		return
	var ratio := clampf(float(health) / float(max_health), 0.0, 1.0)
	var hurt := ratio < 1.0 and health > 0
	_health_bg.visible = hurt
	_health_fill.visible = hurt
	_health_fill.scale.x = ratio
	# Green once it is munchable, matching the body tint cue.
	_health_fill.color = Color(0.5, 0.95, 0.45) if weakened else Color(0.95, 0.35, 0.3)


func _on_hitbox_body_entered(body: Node2D) -> void:
	if body is Player:
		body.hurt(contact_damage, defeat_source)


func take_damage(amount: int) -> void:
	health -= amount
	Juice.damage_number(global_position, amount)
	_refresh_health_bar()
	_on_damaged()
	if health <= 0:
		die()
	elif not weakened and health <= int(max_health * weaken_ratio):
		weakened = true
		_refresh_health_bar()
		Events.enemy_weakened.emit()
		_on_weakened()


## Flame Draft ignites enemies (§12): periodic damage over a few ticks.
func apply_burn(damage_per_tick: int, ticks: int) -> void:
	burn_damage = maxi(burn_damage, damage_per_tick)
	burn_ticks = maxi(burn_ticks, ticks)
	_on_burn_changed(true)
	_burn_timer.start()


func _on_burn_tick() -> void:
	if burn_ticks <= 0:
		_burn_timer.stop()
		_on_burn_changed(false)
		return
	burn_ticks -= 1
	take_damage(burn_damage)


## Monster Munch: only weakened enemies can be consumed (§7).
func can_be_munched() -> bool:
	return weakened


func consume() -> void:
	GameManager.record_enemy_consumed()
	GameManager.add_currency(currency_reward)
	queue_free()


## Override for hit feedback (flash, sound, knockback).
func _on_damaged() -> void:
	Sfx.play("enemy_hit", 0.12)
	Juice.hit_spark(global_position)


## Override to show the munchable state (tint, wobble).
func _on_weakened() -> void:
	pass


## Override to show/clear the ignited state.
func _on_burn_changed(_burning: bool) -> void:
	pass


func die() -> void:
	GameManager.record_enemy_defeated()
	Sfx.play("enemy_death", 0.1)
	Juice.enemy_death(global_position, death_color)
	Juice.shake(4.0, 0.2)
	_drop_premiums()
	queue_free()


func _drop_premiums() -> void:
	if premium_scene == null:
		GameManager.add_currency(currency_reward)
		return
	var parent := get_parent()
	if parent == null:
		GameManager.add_currency(currency_reward)
		return
	for i in premium_drops:
		var premium: Node2D = premium_scene.instantiate()
		premium.global_position = global_position
		var spread := float(i) / maxf(float(premium_drops - 1), 1.0) - 0.5
		premium.pop(Vector2(spread * 200.0, -300.0))
		parent.add_child(premium)
