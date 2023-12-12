extends EnemyState
class_name EnemyIdle

@export var enemy: CharacterBody2D
@export var move_speed := 10.0

var move_direction : Vector2
var wander_time : float

func randomize_wander():
	move_direction = Vector2(randf_range(-1, 1), randf_range(-1, 1))
	wander_time = randf_range(1, 3)
	
func enter():
	randomize_wander()
	
func update(delta):
	if wander_time > 0:
		wander_time -= delta
	else: 
		randomize_wander()

func physics_update(delta):
	if enemy:
		enemy.velocity = move_direction * move_speed

	var direction = PlayerManager.player.global_position - enemy.global_position
	if direction.length() < 30 and direction.length() > 15:
		print("follow")
		Transitioned.emit(self, "EnemyFollow")
