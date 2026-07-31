extends EnemyState
class_name EnemyFollow

@export var enemy: Enemy
@export var move_speed := 10
@export var next_state: EnemyState


func enter():
	enemy.attack_range.body_entered.connect(_body_entered)

func physics_update(delta):
	var direction = PlayerManager.player.global_position - enemy.global_position
	
	var dir = enemy.to_local(enemy.navigation_agent_2d.get_next_path_position()).normalized()
	enemy.velocity = dir.normalized() * move_speed


func _body_entered(body: Node2D):
		if body is Player:
			Transitioned.emit(self, next_state.name)
