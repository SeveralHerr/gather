extends EnemyState
class_name EnemyAttack

@export var enemy: CharacterBody2D



func enter():
	#direction = PlayerManager.player.global_position - enemy.global_position

	_on_attack()
	if not enemy.attack_timer.timeout.is_connected(_on_attack):
		enemy.attack_timer.timeout.connect(_on_attack)
	
	#enemy.collision.disabled = true
	#enemy.soft_collision.disabled = true
	enemy.attack_timer.start()

func physics_update(delta):
	var direction = PlayerManager.player.global_position - enemy.global_position
	enemy.velocity = Vector2.ZERO

	if  direction.length() > 15:
		enemy.attack_timer.stop()
		Transitioned.emit(self, "EnemyIdle")

func _on_attack():
	if enemy.attack_target == null:
		return
		
	if enemy.attack_target is Player:
		enemy.attack_target.receive_hit(Vector2.ZERO, 3)
	
