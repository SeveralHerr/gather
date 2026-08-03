extends EnemyState
class_name EnemyAttack

@export var enemy: CharacterBody2D



func enter():
	_on_attack()
	if not enemy.attack_timer.timeout.is_connected(_on_attack):
		enemy.attack_timer.timeout.connect(_on_attack)
	
	enemy.attack_timer.start()


## attack_timer belongs to the Enemy, not to this state, so a connection made here outlives
## the state unless it is undone. EnemyLunge connects to the SAME timer, and on the bone
## path (Idle-Follow-Anticipate-Lunge-Attack) its _on_lunge_end is connected first — so the
## first timeout inside EnemyAttack also ran EnemyLunge's handler, whose attack_timer.stop()
## is not filtered by anything. enemy_state_machine.gd:27 drops a Transitioned from a
## non-current state, but it cannot drop a side effect. The enemy went permanently quiet
## after its first lunge, with no error anywhere (gather-8fn).
func exit():
	if enemy == null or enemy.attack_timer == null:
		return
	if enemy.attack_timer.timeout.is_connected(_on_attack):
		enemy.attack_timer.timeout.disconnect(_on_attack)
	enemy.attack_timer.stop()


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
		# enemy.damage, not a literal 3. The export existed and was dead: every enemy in
		# the game hit for the same amount no matter what its scene said.
		enemy.attack_target.receive_hit(Vector2.ZERO, enemy.damage)
	
