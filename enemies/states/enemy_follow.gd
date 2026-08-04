extends EnemyState
class_name EnemyFollow

@export var enemy: Enemy
@export var move_speed := 10
@export var next_state: EnemyState

## ## Getting unstuck
##
## There is no baked navigation in this game. `assets/tilesets/world_tile_set.tres` declares
## navigation source groups, but nothing in `main.tscn` is a NavigationRegion2D, so there is no
## navigation map for the agent to path across — `get_next_path_position()` hands back a point
## on the straight line to the target. Walk that line into a tree and the body simply stops:
## `velocity` is written every physics frame, `move_and_slide()` cancels it against the
## collider, and the enemy stands there pushing.
##
## That was invisible for as long as chasing was a close-quarters thing. `EnemyIdle` only gives
## chase inside `Enemy.hunt_range`, which is 30px for an ambient wanderer — two tiles, rarely
## anything in the way. Night raids (gather-0ez) are the first thing in the game that asks an
## enemy to cross an island, and one raider jammed behind a rock is a raid that can never be
## cleared: the banner counts an enemy the player cannot find and the night expires unrewarded.
##
## The fix is deliberately the cheap one rather than baking navigation, which is a change to the
## tilemap, the save format's terrain replay and every scene tile that writes a cell. When the
## body has failed to move for STUCK_AFTER seconds while it was trying to, it slides along the
## obstacle for SIDESTEP_TIME and then re-aims. Two or three of those get a raider around
## anything the world generator produces, and it costs one Vector2 compare per enemy per frame.
##
## It is on the follow state rather than on the raider so that every chase benefits, and because
## a stuck ambient enemy is also a bug — it was simply one nobody could see.

## How long the body must fail to make progress before the sidestep engages. Long enough that
## ordinary collision jostling — two enemies overlapping, a corner clipped — does not trigger it.
const STUCK_AFTER := 0.45

## How far the body must move in a frame to count as progress, in world pixels per second.
## Compared against the frame's actual displacement over its delta, so it is independent of
## frame rate. Well under `move_speed` (10) and well over the sub-pixel drift of a body pressed
## against a wall, which measured ~0.02.
const STUCK_SPEED := 2.0

## How long one sidestep runs before the enemy re-aims at the target. Long enough to clear a
## 16px tile at move_speed, short enough that an enemy which is not really stuck loses at most
## this much ground.
const SIDESTEP_TIME := 0.7

## Where the body was on the previous physics frame, for the progress test.
var _last_position := Vector2.ZERO

## Seconds of no progress accumulated so far, and how much of the current sidestep is left.
var _stuck_time := 0.0
var _sidestep_left := 0.0

## Which way this sidestep goes, +1 or -1. Chosen once when the sidestep starts rather than per
## frame: a sign re-rolled every frame averages to standing still, which is the bug it is meant
## to fix wearing a different hat.
var _sidestep_sign := 1.0


func enter():
	# Guarded, and matched by a disconnect in exit(). Re-entering follow (attack -> follow is
	# the normal cycle) reconnected the same callable, and Godot answers that with an
	# "already connected" error on every transition — noise during any ordinary fight, and a
	# double-firing transition the moment someone swaps this for CONNECT_REFERENCE_COUNTED
	# (gather-0du).
	if enemy == null or enemy.attack_range == null:
		return

	# Reset the stuck tracker on every entry. Follow is re-entered constantly (attack -> follow
	# is the normal cycle), and a `_last_position` left over from the previous chase makes the
	# first frame back look like a huge jump or like no progress at all, depending on where the
	# fight moved to.
	_last_position = enemy.global_position
	_stuck_time = 0.0
	_sidestep_left = 0.0

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
	if enemy == null:
		return

	var dir: Vector2 = enemy.to_local(enemy.navigation_agent_2d.get_next_path_position()).normalized()

	# A zero direction means the agent has nothing to say — no target, or the next path position
	# is exactly where we already are. Steering off it would normalize (0,0) into (0,0) and the
	# sidestep below would have no axis to be perpendicular to.
	if dir == Vector2.ZERO:
		enemy.velocity = Vector2.ZERO
		_last_position = enemy.global_position
		return

	_update_stuck(delta)

	if _sidestep_left > 0.0:
		_sidestep_left -= delta
		# Perpendicular to the way we wanted to go, with a little of the original mixed back in
		# so the enemy slides ALONG the obstacle rather than straight out from it — the pure
		# perpendicular walks back and forth across the same face forever on a long wall.
		dir = (dir.orthogonal() * _sidestep_sign + dir * 0.35).normalized()

	enemy.velocity = dir * move_speed


## Accumulates "I asked to move and did not", and starts a sidestep once that has gone on long
## enough. See the block comment at the top of this file for why this is needed at all.
##
## Measures actual displacement rather than reading `velocity`: `velocity` is what we *wrote*
## and is nonzero the entire time a body is pressed against a wall. What moves is the position,
## and it is the only honest signal available.
func _update_stuck(delta: float) -> void:
	if delta <= 0.0:
		return

	# Already sidestepping — do not accumulate on top of it, or a sidestep that is itself blocked
	# retriggers immediately and the sign never gets a chance to be tried the other way.
	if _sidestep_left > 0.0:
		_last_position = enemy.global_position
		return

	var moved := enemy.global_position.distance_to(_last_position)
	_last_position = enemy.global_position

	if moved / delta >= STUCK_SPEED:
		_stuck_time = 0.0
		return

	_stuck_time += delta
	if _stuck_time < STUCK_AFTER:
		return

	_stuck_time = 0.0
	_sidestep_left = SIDESTEP_TIME
	# Re-rolled per episode, so an enemy that picks the wrong way round an obstacle gets the
	# other way on its next attempt instead of grinding against the same corner forever.
	_sidestep_sign = 1.0 if randf() < 0.5 else -1.0


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
