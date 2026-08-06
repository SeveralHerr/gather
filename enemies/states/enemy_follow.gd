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
## on the straight line to the target. Walk that line into a wall and the body simply stops:
## `velocity` is written every physics frame, `move_and_slide()` cancels it against the
## collider, and the enemy stands there pushing.
##
## That was invisible for as long as chasing was a close-quarters thing. `EnemyIdle` only gives
## chase inside `Enemy.hunt_range`, which is 30px for an ambient wanderer — two tiles, rarely
## anything in the way. Night raids (gather-0ez) are the first thing in the game that asks an
## enemy to cross an island, and one raider jammed behind a wall is a raid that can never be
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
##
## ## What changed when props left the collision layer
##
## Trees, rocks and bushes moved to physics bit 8 and off the movement layer, so enemies now walk
## straight through them. That shrinks the obstacle set to the things the player BUILT — walls
## and doors — which are flat faces and right-angled corners rather than the scattered round
## things this originally coped with. So the sidestep is no longer a blind coin flip: the wall
## itself says which way it faces, via `get_slide_collision(i).get_normal()` after the body's own
## `move_and_slide()`, and `sidestep_sign_for` turns that into the direction that keeps most of
## the heading we wanted. The coin flip survives only as the fallback for the head-on case, where
## the wall genuinely has nothing to say — see that function.
##
## ## Losing sight of the player, and why the enemy does not forget instantly
##
## `EnemyIdle` will not START a chase through a wall (see its class comment). Applying the same
## rule here would mean an enemy dropping the chase on the exact frame the player steps behind
## cover, which does not read as stealth — it reads as the AI switching off. So a chase already
## under way survives GIVE_UP_AFTER seconds of no sight, during which the enemy heads for where
## it last saw the player and then stands there for the remainder before wandering off. Arriving
## at the last known spot and looking around is what makes a lost chase legible; snapping back to
## a wander in the same frame is what makes it look broken.
##
## Raiders never lose the player at all, and that exemption is load-bearing rather than an
## oversight — `Enemy.hunts_through_walls_for` carries the argument.

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

## Below this, the heading and the wall's normal are close enough to parallel that both ways
## along the wall are equally good and the contact cannot break the tie. Compared against a dot
## product of two unit-ish vectors, so it is a cosine: 0.15 is about 8.6 degrees off head-on.
const HEAD_ON_EPSILON := 0.15

## How long a chase survives with no line of sight before the enemy gives up and returns to idle.
##
## 2.5s is roughly "round the corner and one room further" at move_speed 10 — long enough that
## ducking behind a wall does not switch the enemy off mid-swing, short enough that a player who
## has genuinely broken away is not shadowed across the island by something that cannot see them.
const GIVE_UP_AFTER := 2.5

## How close to the last known position counts as having arrived at it. One tile: any tighter and
## the body jitters around a point it cannot land on exactly, which reads as a twitch rather than
## as a search.
const ARRIVED_RADIUS := 16.0

## Where the body was on the previous physics frame, for the progress test.
var _last_position := Vector2.ZERO

## Seconds of no progress accumulated so far, and how much of the current sidestep is left.
var _stuck_time := 0.0
var _sidestep_left := 0.0

## Which way this sidestep goes, +1 or -1. Chosen once when the sidestep starts rather than per
## frame: a sign re-rolled every frame averages to standing still, which is the bug it is meant
## to fix wearing a different hat.
var _sidestep_sign := 1.0

## The vision state: whether the last check could see the player, where the player was when it
## last could, how long it has been since, and the throttle for the check itself.
var _has_los := true
var _last_known_position := Vector2.ZERO
var _lost_los_time := 0.0
var _los_cooldown := 0.0


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

	# Every entry into follow is an engagement: EnemyIdle only sends one after confirming sight,
	# and the lunge/attack cycle sends one from point-blank range. So the chase starts believing
	# it can see the player and the grace period starts at zero. The throttle is phase-offset per
	# enemy for the reason EnemyIdle's class comment gives.
	_has_los = true
	_lost_los_time = 0.0
	_los_cooldown = Enemy.los_stagger_offset(enemy.get_instance_id(), Enemy.LOS_RECHECK_SECONDS)
	var player := PlayerManager.player
	_last_known_position = player.global_position if player != null else enemy.global_position

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

	_update_vision(delta)

	if should_give_up(_lost_los_time, GIVE_UP_AFTER, enemy.hunts_through_walls()):
		enemy.velocity = Vector2.ZERO
		Transitioned.emit(self, "EnemyIdle")
		return

	var dir := _desired_direction()

	# A zero direction means either the agent has nothing to say — no target, or the next path
	# position is exactly where we already are — or we have arrived at the last place the player
	# was seen and are standing there looking around. Steering off it would normalize (0,0) into
	# (0,0) and the sidestep below would have no axis to be perpendicular to.
	if dir == Vector2.ZERO:
		enemy.velocity = Vector2.ZERO
		_last_position = enemy.global_position
		return

	_update_stuck(delta, dir)

	if _sidestep_left > 0.0:
		_sidestep_left -= delta
		# Perpendicular to the way we wanted to go, with a little of the original mixed back in
		# so the enemy slides ALONG the obstacle rather than straight out from it — the pure
		# perpendicular walks back and forth across the same face forever on a long wall.
		dir = (dir.orthogonal() * _sidestep_sign + dir * 0.35).normalized()

	enemy.velocity = dir * move_speed


# --- vision ------------------------------------------------------------------


## Whether a chase that has gone `lost_seconds` without sight is over.
##
## Pure and static so a headless test can assert the grace period without a physics world, which
## is the only place the wall itself can be stood up. `hunts_through_walls` short-circuits it
## entirely rather than being folded into the timer, so a raider's chase has no expiry to get
## wrong rather than one set to infinity.
static func should_give_up(lost_seconds: float, grace: float, hunts_through_walls: bool) -> bool:
	if hunts_through_walls:
		return false
	return lost_seconds >= grace


## Re-checks line of sight on the throttle, and keeps the last-known position and the give-up
## clock in step with the answer.
##
## The throttled check means `_lost_los_time` is accurate to within one recheck period, which is
## deliberate and harmless: it is compared against a 2.5s grace, so a 0.3s granularity moves the
## give-up by at most a frame's worth of what the player would notice.
func _update_vision(delta: float) -> void:
	var player := PlayerManager.player
	if player == null:
		return

	# Raiders never lose the player, and never pay for a raycast to be told so. See
	# `Enemy.hunts_through_walls_for`.
	if enemy.hunts_through_walls():
		_has_los = true
		_lost_los_time = 0.0
		_last_known_position = player.global_position
		return

	_los_cooldown -= delta
	if _los_cooldown <= 0.0:
		_los_cooldown = Enemy.LOS_RECHECK_SECONDS
		_has_los = enemy.has_line_of_sight_to(player.global_position)

	if _has_los:
		_lost_los_time = 0.0
		_last_known_position = player.global_position
	else:
		_lost_los_time += delta


## Where to steer this frame, in the enemy's local space.
##
## With sight, the navigation agent as before. Without it, the last known position — NOT the
## agent, which is fed `enemy.target` by `Enemy.create_path()` on a timer and happily keeps
## tracking a player it cannot see. Reading the agent during the grace period would make the
## grace a delayed version of the old behaviour rather than a search, and the enemy would round
## the corner at exactly the moment it was supposed to give up.
func _desired_direction() -> Vector2:
	if _has_los:
		return enemy.to_local(enemy.navigation_agent_2d.get_next_path_position()).normalized()

	var to_last := _last_known_position - enemy.global_position
	if to_last.length() <= ARRIVED_RADIUS:
		return Vector2.ZERO
	return to_last.normalized()


# --- getting unstuck ---------------------------------------------------------


## Accumulates "I asked to move and did not", and starts a sidestep once that has gone on long
## enough. See the block comment at the top of this file for why this is needed at all.
##
## Measures actual displacement rather than reading `velocity`: `velocity` is what we *wrote*
## and is nonzero the entire time a body is pressed against a wall. What moves is the position,
## and it is the only honest signal available.
func _update_stuck(delta: float, dir: Vector2) -> void:
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
	# The wall is asked first; the coin flip is only what happens when it has no answer. Re-rolled
	# per episode in that case, so an enemy which picks the wrong way round an obstacle gets the
	# other way on its next attempt instead of grinding against the same corner forever.
	var coin := 1.0 if randf() < 0.5 else -1.0
	_sidestep_sign = sidestep_sign_for(dir, _blocking_normal(dir), coin)


## The face of whatever we are walking into: the slide collision whose normal most opposes `dir`.
##
## Read after the body's own `move_and_slide()` and before the next one, which is exactly where
## this runs — `Enemy._physics_process` slides the body, and Godot ticks a parent before its
## children, so the StateMachine (and therefore this state) sees the collisions from the frame
## that just moved. Zero when nothing was hit, which is the honest answer for an enemy that is
## stuck for some reason other than a wall (jammed between two other enemies, say) and is what
## makes `sidestep_sign_for` fall back rather than invent a direction.
func _blocking_normal(dir: Vector2) -> Vector2:
	if enemy == null:
		return Vector2.ZERO

	var best := Vector2.ZERO
	var best_dot := 0.0
	for i in enemy.get_slide_collision_count():
		var contact := enemy.get_slide_collision(i)
		if contact == null:
			continue
		var normal := contact.get_normal()
		var opposition := dir.dot(normal)
		if opposition < best_dot:
			best_dot = opposition
			best = normal
	return best


## Which way to slide along a wall, as the +1/-1 the sidestep multiplies `dir.orthogonal()` by.
##
## The two ways along a wall whose face points `wall_normal` are its two orthogonals; the useful
## one is whichever keeps more of the heading we actually wanted. Rotating both vectors by the
## same 90 degrees preserves their dot product, which is why the answer collapses to the sign of
## `desired . wall_normal.orthogonal()`, negated because we are walking INTO the face.
##
## Two cases hand back `fallback` rather than a guess, and both matter:
##
##  * Head-on. `desired` square into the wall leaves both directions exactly as good, and a
##    formula that picked one anyway would pick the SAME one every time for a given approach —
##    an enemy that grinds into the same corner of a house forever, which is worse than the coin
##    flip this replaced because it is deterministic.
##  * Not actually into this face. If the dot with the normal is positive we are moving away from
##    it and it is not what stopped us; steering off it would send the enemy somewhere unrelated
##    to what is blocking it.
##
## Pure and static: the geometry is the part that is easy to get subtly backwards, and it is the
## part a headless test can pin exactly.
static func sidestep_sign_for(desired: Vector2, wall_normal: Vector2, fallback: float) -> float:
	if desired == Vector2.ZERO or wall_normal == Vector2.ZERO:
		return fallback

	var into := desired.dot(wall_normal)
	if into >= 0.0:
		return fallback

	var along := desired.dot(wall_normal.orthogonal())
	if absf(along) < HEAD_ON_EPSILON:
		return fallback

	return -signf(along)


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
