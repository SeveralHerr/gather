extends EnemyState
class_name EnemyAnticipate

@export var enemy: CharacterBody2D
@export var enemy_follow: Node

const LUNGE_TEXTURE = preload("res://Enemies/lunge_texture.tscn")
var direction
var instance

func enter():
	direction = PlayerManager.player.global_position - enemy.global_position
	instance = LUNGE_TEXTURE.instantiate()
	enemy.add_child(instance)
	instance.rotation = PlayerManager.player.global_position.angle_to_point(enemy.position)
	
	enemy.velocity = Vector2.ZERO
	await get_tree().create_timer(1).timeout

	instance.queue_free()
	enemy_follow.direction = direction
	Transitioned.emit(self, "EnemyLunge")

