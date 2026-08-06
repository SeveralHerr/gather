extends EnemyState
class_name EnemyIdle

@export var enemy: CharacterBody2D
@export var move_speed := 10.0
@export var attack_range: int

## ## Why a chase now costs a raycast
##
## This state used to start a chase on straight-line distance and nothing else. A player standing
## inside their own walled house therefore had skeletons pressed against the outside of the wall,
## pathing at them forever — the one thing the player had built specifically so that would not
## happen. Nothing errored and nothing looked broken from the code's side; the enemies were doing
## exactly what they were told.
##
## The gate is a ray masked to `Enemy.STRUCTURE_COLLISION_LAYER` (bit 7), which carries walls and
## doors and nothing else. That mask is the whole reason this is affordable and the whole reason
## it reads correctly: a ray against the movement layer would also stop a chase for a tree, and
## an enemy that will not come round a sapling is not stealth, it is a broken enemy.
##
## ## The two costs, and how each is paid
##
## `physics_update` runs every physics tick on every live enemy, and a night raid can put dozens
## on the map. So the ray is gated behind the distance test that was already here — nothing
## outside `hunt_range` ever raycasts, which is almost every enemy almost always — and then
## throttled to one query per `Enemy.LOS_RECHECK_SECONDS`, phase-offset per enemy so a clump does
## not synchronise onto one tick. The cached answer is what the transition reads in between.
##
## Two consequences worth stating so a later reader does not "fix" them:
##
##  * An enemy that has just come into range waits up to one recheck period before it can notice
##    the player. That is the stagger doing its job, it is under a third of a second, and it is
##    invisible next to the wander this state is already doing.
##  * The cache is dropped (and the phase re-seeded) whenever the player leaves `hunt_range`, so
##    a stale "yes I can see you" from before a wall was built cannot survive into a later
##    approach.

## The last answer the raycast gave, and how long until it is asked again. `false` until the
## first check, so the frame an enemy comes into range never chases on an uninitialised yes.
var _can_see_player := false
var _los_cooldown := 0.0

var move_direction : Vector2
var wander_time : float

func randomize_wander():
	move_direction = Vector2(randf_range(-1, 1), randf_range(-1, 1))
	wander_time = randf_range(1, 3)

func enter():
	randomize_wander()
	_forget_line_of_sight()

func update(delta):
	if wander_time > 0:
		wander_time -= delta
	else:
		randomize_wander()


## Whether the player is in the band this state chases from at all: near enough to notice, far
## enough that the attack states are not already the right answer.
##
## Pure and static, split out from the transition below, because "does distance say hunt" and
## "does the wall say hunt" are two questions that fail differently and a headless test cannot
## stand up a physics world to ask the second.
static func in_hunt_band(distance: float, hunt_range: float, attack_range: float) -> bool:
	return distance < hunt_range and distance > attack_range


## The whole decision, as one pure function.
##
## `has_los` is only consulted when the enemy respects it — see `Enemy.hunts_through_walls_for`
## for why raiders do not, which is the single most surprising line in this file if you meet it
## without that comment.
static func should_hunt(distance: float, hunt_range: float, attack_range: float,
		hunts_through_walls: bool, has_los: bool) -> bool:
	if not in_hunt_band(distance, hunt_range, attack_range):
		return false
	return hunts_through_walls or has_los


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
	var distance := direction.length()

	# The cheap half first, and it is the reason the expensive half is affordable: an enemy the
	# player is nowhere near never touches the physics server at all.
	if not in_hunt_band(distance, enemy.hunt_range, attack_range):
		_forget_line_of_sight()
		return

	var through_walls: bool = enemy.hunts_through_walls()
	if not through_walls:
		_los_cooldown -= delta
		if _los_cooldown <= 0.0:
			_los_cooldown = Enemy.LOS_RECHECK_SECONDS
			_can_see_player = enemy.has_line_of_sight_to(player.global_position)

	if should_hunt(distance, enemy.hunt_range, attack_range, through_walls, _can_see_player):
		Transitioned.emit(self, "EnemyFollow")


## Drops the cached answer and re-seeds the throttle's phase from this enemy's instance id.
##
## Called on entry and whenever the player leaves the band, so the next approach starts from an
## honest check rather than from whatever the answer was last time the player was near — the
## world between the two may now contain a wall that was not there before.
func _forget_line_of_sight() -> void:
	_can_see_player = false
	_los_cooldown = 0.0
	if enemy != null:
		_los_cooldown = Enemy.los_stagger_offset(enemy.get_instance_id(), Enemy.LOS_RECHECK_SECONDS)
