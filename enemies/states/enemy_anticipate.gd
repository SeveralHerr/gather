extends EnemyState
class_name EnemyAnticipate

@export var enemy: CharacterBody2D
@export var enemy_follow: Node

const LUNGE_TEXTURE = preload("res://enemies/lunge_texture.tscn")
var direction
var instance

## THIS add_child RUNS INSIDE A PHYSICS CALLBACK, and is safe only by accident (gather-im1).
##
## The path is enemy_follow.gd's _body_entered — an Area2D signal, so the physics server is
## mid-flush and holds the space locked — then Transitioned, then
## enemy_state_machine.gd:37 new_state.enter(), i.e. here. bone_enemy.tscn wires
## EnemyFollow.next_state to EnemyAnticipate, so this happens on every single engagement.
##
## What keeps it legal is that enemies/lunge_texture.tscn is a bare Sprite2D with NO
## collision node: adding a node with no physics body creates nothing the locked space has to
## accept. Give the telegraph a hitbox — an obvious thing to want, since it is the wind-up to
## a lunge — and this becomes a locked-space write, which Godot refuses with "Function
## blocked during in/out signal" while the state machine carries on as though it worked.
##
## If that ever changes, the fix is call_deferred("add_child", instance), not a rewrite.
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

