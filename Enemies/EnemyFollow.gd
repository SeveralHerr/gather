extends EnemyState
class_name EnemyFollow

@export var enemy: CharacterBody2D
@export var move_speed := 10
@export var next_state: EnemyState
@export var attack_range: int

func physics_update(delta):
	var direction = PlayerManager.player.global_position - enemy.global_position
	
	if direction.length() > attack_range:
		var dir = enemy.to_local(enemy.navigation_agent_2d.get_next_path_position()).normalized()
		enemy.velocity = dir.normalized() * move_speed
	else:
		enemy.velocity = Vector2()
		Transitioned.emit(self, next_state.name)

	if direction.length() > 50:
		Transitioned.emit(self, "EnemyIdle")
		
	if direction.length() < attack_range:
		Transitioned.emit(self, next_state.name)

