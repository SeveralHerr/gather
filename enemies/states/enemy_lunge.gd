extends EnemyState
class_name EnemyLunge

@export var enemy: CharacterBody2D
@export var lunge_speed := 40

var direction


func enter():
	#direction = PlayerManager.player.global_position - enemy.global_position

	
	if not enemy.attack_timer.timeout.is_connected(_on_lunge_end):
		enemy.attack_timer.timeout.connect(_on_lunge_end)
	
	#enemy.collision.disabled = true
	#enemy.soft_collision.disabled = true
	enemy.attack_timer.start()


## The other half of the shared-timer leak this state is one of the two authors of. Left
## connected, _on_lunge_end fired during EnemyAttack and stopped the attack timer for good;
## symmetrically, EnemyAttack's handler fired during this lunge and landed a free hit in the
## windup. See enemy_attack.gd's exit() and gather-8fn.
func exit():
	if enemy == null or enemy.attack_timer == null:
		return
	if enemy.attack_timer.timeout.is_connected(_on_lunge_end):
		enemy.attack_timer.timeout.disconnect(_on_lunge_end)
	enemy.attack_timer.stop()


func physics_update(delta):
	var current_direction = PlayerManager.player.global_position - enemy.global_position
	enemy.velocity = direction.normalized() * 50
	
	if  current_direction.length() < 10:
		enemy.attack_timer.stop()
		Transitioned.emit(self, "EnemyAttack")

func _on_lunge_end():
	enemy.attack_timer.stop()
	Transitioned.emit(self, "EnemyFollow")
	
