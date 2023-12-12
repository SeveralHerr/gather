extends EnemyState
class_name EnemyLunge

@export var enemy: CharacterBody2D
@export var lunge_speed := 40

var direction

func enter():
	direction = PlayerManager.player.global_position - enemy.global_position
	
	if not enemy.attack_timer.timeout.is_connected(_on_lunge_end):
		enemy.attack_timer.timeout.connect(_on_lunge_end)
	
	#enemy.collision.disabled = true
	#enemy.soft_collision.disabled = true
	enemy.attack_timer.start()

func physics_update(delta):
	var current_direction = PlayerManager.player.global_position - enemy.global_position
	enemy.velocity = direction.normalized() * 50
	
	if  current_direction.length() < 10:
		print("idle < 10")
		_on_attack()
		enemy.attack_timer.stop()
		Transitioned.emit(self, "EnemyIdle")

func _on_lunge_end():
	enemy.attack_timer.stop()
	print("timer")
	Transitioned.emit(self, "EnemyIdle")
	
func _on_attack():
	if enemy.attack_target == null:
		return
		
	if enemy.attack_target is Player:
		enemy.attack_target.receive_hit(Vector2.ZERO, 3)
