class_name EnemyBase
extends CharacterBody2D
## Reusable enemy foundation (GAME_DESIGN.md §16, §29): health, contact
## damage, defeat rewards, and off-screen processing pause (§30).

@export var max_health: int = 30
@export var contact_damage: int = 10
@export var currency_reward: int = 5
@export var defeat_source: String = "unknown enemy"

var health: int

@onready var hitbox: Area2D = $Hitbox
@onready var visibility_notifier: VisibleOnScreenNotifier2D = $OnScreen


func _ready() -> void:
	health = max_health
	hitbox.body_entered.connect(_on_hitbox_body_entered)
	# Pause processing while off screen (§30).
	visibility_notifier.screen_entered.connect(func() -> void: set_physics_process(true))
	visibility_notifier.screen_exited.connect(func() -> void: set_physics_process(false))
	set_physics_process(false)


func _on_hitbox_body_entered(body: Node2D) -> void:
	if body is Player:
		body.hurt(contact_damage, defeat_source)


func take_damage(amount: int) -> void:
	health -= amount
	_on_damaged()
	if health <= 0:
		die()


## Override for hit feedback (flash, sound, knockback).
func _on_damaged() -> void:
	pass


func die() -> void:
	GameManager.record_enemy_defeated()
	GameManager.add_currency(currency_reward)
	queue_free()
