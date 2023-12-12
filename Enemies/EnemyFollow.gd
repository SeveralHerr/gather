extends EnemyState
class_name EnemyFollow

@export var enemy: CharacterBody2D
@export var move_speed := 10

func physics_update(delta):
	var direction = PlayerManager.player.global_position - enemy.global_position
	
	if direction.length() > 15:
		var dir = enemy.to_local(enemy.navigation_agent_2d.get_next_path_position()).normalized()
		enemy.velocity = dir.normalized() * move_speed
	else:
		enemy.velocity = Vector2()

	if direction.length() > 50:
		print("idle > 50")
		Transitioned.emit(self, "EnemyIdle")
		
	if direction.length() < 25:
		print ("lunge")
		Transitioned.emit(self, "EnemyLunge")

