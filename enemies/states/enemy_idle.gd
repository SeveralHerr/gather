extends EnemyState
class_name EnemyIdle

@export var enemy: CharacterBody2D
@export var move_speed := 10.0
@export var attack_range: int

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

	# The player may not exist for a frame around a load or a respawn, and this runs every
	# physics tick on every live enemy — so an unguarded read here is a flood of errors at
	# exactly the moment the log is worth reading.
	var player := PlayerManager.player
	if player == null or enemy == null:
		return

	# `enemy.hunt_range` rather than the literal 30 this used to carry. Ambient enemies still
	# get 30 from Enemy's default, so nothing about the ordinary island changed; the raider
	# scenes set it wide enough to cross the map, which is what makes a raid arrive.
	var direction = player.global_position - enemy.global_position
	if direction.length() < enemy.hunt_range and direction.length() > attack_range:
		Transitioned.emit(self, "EnemyFollow")
