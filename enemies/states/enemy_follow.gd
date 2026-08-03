extends EnemyState
class_name EnemyFollow

@export var enemy: Enemy
@export var move_speed := 10
@export var next_state: EnemyState


func enter():
	# Guarded, and matched by a disconnect in exit(). Re-entering follow (attack -> follow is
	# the normal cycle) reconnected the same callable, and Godot answers that with an
	# "already connected" error on every transition — noise during any ordinary fight, and a
	# double-firing transition the moment someone swaps this for CONNECT_REFERENCE_COUNTED
	# (gather-0du).
	if enemy == null or enemy.attack_range == null:
		return
	if not enemy.attack_range.body_entered.is_connected(_body_entered):
		enemy.attack_range.body_entered.connect(_body_entered)


func exit():
	if enemy == null or enemy.attack_range == null:
		return
	if enemy.attack_range.body_entered.is_connected(_body_entered):
		enemy.attack_range.body_entered.disconnect(_body_entered)

func physics_update(delta):
	var direction = PlayerManager.player.global_position - enemy.global_position
	
	var dir = enemy.to_local(enemy.navigation_agent_2d.get_next_path_position()).normalized()
	enemy.velocity = dir.normalized() * move_speed


func _body_entered(body: Node2D):
		if body is Player:
			Transitioned.emit(self, next_state.name)
