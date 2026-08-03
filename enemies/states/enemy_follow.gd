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

	# body_entered fires on ENTRY, so a player who is ALREADY inside the area when this state
	# starts never generates one and the enemy follows forever at point-blank range. Connecting
	# a handler and then never checking the bodies already in the area is the standard shape of
	# that bug; this is the standard fix (gather-83d).
	#
	# It is the second half of a fight rather than the first that gets here: EnemyAttack drops
	# to EnemyIdle once the player is more than 15 units away, EnemyIdle re-enters follow at 30,
	# and the attack area is wider than that gap on the bone enemy — so a player who backs off
	# a step and stops is inside the area with no entry event coming.
	_transition_if_player_in_range()


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


## Emits the same transition _body_entered would, for a player already standing in the area.
##
## Split out rather than inlined so the two routes into the attack state cannot drift, and so
## a test can drive it without a physics frame — get_overlapping_bodies() is only accurate
## after one, which is the other half of why the entry-event path exists at all.
func _transition_if_player_in_range() -> void:
	if next_state == null or enemy == null or enemy.attack_range == null:
		return
	for body in enemy.attack_range.get_overlapping_bodies():
		if body is Player:
			Transitioned.emit(self, next_state.name)
			return
