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

var health: int
var weakened: bool = false
var burn_ticks: int = 0
var burn_damage: int = 0

@onready var hitbox: Area2D = $Hitbox
@onready var visibility_notifier: VisibleOnScreenNotifier2D = $OnScreen

var _burn_timer: Timer


func _ready() -> void:
	health = max_health
	hitbox.body_entered.connect(_on_hitbox_body_entered)
	# Pause processing while off screen (§30).
	visibility_notifier.screen_entered.connect(func() -> void: set_physics_process(true))
	visibility_notifier.screen_exited.connect(func() -> void: set_physics_process(false))
	set_physics_process(false)
	_burn_timer = Timer.new()
	_burn_timer.wait_time = 0.5
	_burn_timer.timeout.connect(_on_burn_tick)
	add_child(_burn_timer)


func _on_hitbox_body_entered(body: Node2D) -> void:
	if body is Player:
		body.hurt(contact_damage, defeat_source)


func take_damage(amount: int) -> void:
	health -= amount
	_on_damaged()
	if health <= 0:
		die()
	elif not weakened and health <= int(max_health * weaken_ratio):
		weakened = true
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
	pass


## Override to show the munchable state (tint, wobble).
func _on_weakened() -> void:
	pass


## Override to show/clear the ignited state.
func _on_burn_changed(_burning: bool) -> void:
	pass


func die() -> void:
	GameManager.record_enemy_defeated()
	GameManager.add_currency(currency_reward)
	queue_free()
