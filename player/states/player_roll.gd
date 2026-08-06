extends PlayerState
class_name PlayerRoll

## The dodge roll: a short committed burst in the direction the player is already going, with
## invulnerability across the burst, and a recovery that pays for the ground it covered.
##
## ## Why the recovery is exactly this long
##
## The design constraint is "a roll should cover more ground than walking, but rolling on
## repeat must not be a faster way to cross the island than walking" — otherwise the roll
## stops being a defensive option and becomes the movement the player uses for everything,
## which is both worse to watch and worse to play.
##
## A **cooldown cannot enforce that on its own**, and this is the part that is easy to get
## wrong: whatever the player is not rolling through, they are *walking* through, so a longer
## cooldown just adds neutral walking time to the cycle and leaves the per-cycle surplus
## exactly where it was. Only time in which the player moves *slower than walking* can pay the
## surplus back. Hence a recovery that roots them:
##
##     surplus per roll = ROLL_TIME * (ROLL_SPEED_MULT - 1)   ... ground gained by the burst
##     debt per roll    = ROLL_RECOVERY                        ... ground lost standing still
##
## and the two are set equal. `sustained_speed_ratio()` below states that as a pure function,
## and `test_player_combat.gd` pins it at 1.0, so a retune of any one of the three constants
## that quietly makes rolling the fastest travel in the game fails a test instead of shipping.
## The cooldown is then free to be a *feel* dial — how often a dodge is available — rather
## than load-bearing arithmetic.
##
## ## Which invulnerability flag, and why not `invulnerable`
##
## `Player.invulnerable` is owned by the respawn sequence: `_grant_invulnerability()` sets it,
## awaits, and clears it unconditionally (`player.gd:57` says so outright). Writing it from
## here would break in both directions, and neither failure would look like a roll bug —
## a respawn grace ending mid-roll would strip the roll's i-frames, and a roll ending inside
## the respawn grace would strip the *respawn's*, killing a player who had just come back and
## was standing in the lap of whatever killed them.
##
## So the roll owns its own flag, `Player.rolling_invulnerable`, and `receive_hit()` checks
## both. Two flags with one owner each is the whole point; a single flag with two owners is
## the bug. This is the same reasoning `god_mode` was split out under.

## Seconds of burst. Short — this is a dodge, not a dash, and the sprite is 16px, so anything
## longer reads as the player sliding rather than as them getting out of the way.
const ROLL_TIME := 0.25

## Burst speed as a multiple of walking. 2.2 covers 27.5px at the base MOVE_SPEED — a bit
## under two tiles, and comfortably past `enemy.gd`'s 18px lunge, so a well-timed roll leaves
## the swing that provoked it behind rather than merely surviving it.
const ROLL_SPEED_MULT := 2.2

## Seconds rooted after the burst. Derived from the two constants above rather than tuned —
## see the header. Changing it away from `ROLL_TIME * (ROLL_SPEED_MULT - 1)` is a deliberate
## decision to make rolling faster or slower than walking, not a feel tweak.
const ROLL_RECOVERY := 0.30

## Seconds from the START of a roll before another may begin. Feel only, per the header: it
## decides how often a dodge is available, not how fast the player travels. Must stay above
## `ROLL_TIME + ROLL_RECOVERY`, or the state releases the player straight into another roll
## and the recovery stops being a recovery.
const ROLL_COOLDOWN := 1.0

## Seconds of invulnerability from the start of the roll. Covers the whole burst plus a small
## tail, so a blow that connects on the frame the burst ends still misses — a dodge that is
## invulnerable for exactly as long as it moves is one the player has to time to the frame,
## and this game is played by children on a phone. It ends well before the state does, which
## is what makes the recovery a genuine exposure rather than a free half-second.
const ROLL_IFRAME_TIME := 0.30

## The squash the sprite takes at the start of the burst, and how much of the burst is spent
## reaching it. There is no roll animation in the AnimationLibrary — the player art is a
## single 16px frame — so the tumble is entirely this, and it is enough: the silhouette
## changing at all is what separates a roll from being shoved.
##
## Deliberately NOT a Light2D, and deliberately not a `modulate` tween: `project.godot` runs
## `gl_compatibility` on mobile with a hard cap on Light2Ds per canvas item (see CLAUDE.md),
## and `modulate:a` on this sprite is already owned by `_grant_invulnerability()`'s blink —
## two tweens on one property is a fight whose loser is whichever finished second.
const ROLL_SQUASH := Vector2(1.35, 0.7)
const ROLL_SQUASH_IN := 0.4

## Seconds left of burst + recovery, i.e. how long the player is committed. Zero when idle.
var _time_left := 0.0

## Seconds left of the burst alone.
var _burst_left := 0.0

var _iframes_left := 0.0

## Seconds until another roll may start. Like PlayerAttack's, this deliberately survives
## `exit()` — see there.
var _cooldown_left := 0.0

var _direction := Vector2.ZERO
var _speed := 0.0
var _tween: Tween


## Whether a roll may start right now. `Player._dodge()` asks BEFORE calling `change_to`,
## which matters: a refusal inside `enter()` would already have run the outgoing state's
## `exit()`, so pressing dodge on cooldown mid-gather would tear the gather's animation and
## selector down for nothing.
func can_roll() -> bool:
	return _cooldown_left <= 0.0


func enter() -> void:
	p = PlayerManager.player
	if p == null:
		return

	# Belt and braces behind `Player._dodge()`'s gate. `change_to("PlayerRoll")` is a public
	# call and this is the one state where entering when it should not have would hand the
	# player free invulnerability.
	if p.is_dead or _cooldown_left > 0.0:
		fsm.change_to("PlayerIdle")
		return

	# A roll cancels a gather, and it has to release the WORK ORDER, not just the picture.
	# PlayerGather.exit() deliberately leaves `ResourceManager2` running — the hold is owned
	# by the release path (see player_gather.gd) — so without this line the mining timer
	# carries on through the roll against a tile the player has just left, and finishes on
	# it. That is gather-3zg's failure reached from a third direction.
	p.resourceManager.stop_removing_resource()

	_direction = roll_direction(p.velocity, p.is_facing_left())
	_speed = Player.MOVE_SPEED * p.stats.move_speed_mult * ROLL_SPEED_MULT
	_burst_left = ROLL_TIME
	_time_left = ROLL_TIME + ROLL_RECOVERY
	_iframes_left = ROLL_IFRAME_TIME
	_cooldown_left = ROLL_COOLDOWN
	p.rolling_invulnerable = true

	_start_squash()
	# TINY is documented as "one swing of a pickaxe ... must not accumulate into a rumble",
	# which is exactly the budget a roll wants: it fires at most once a second, so it can
	# never build, and a dodge that shook the screen like a hit would read as having been hit.
	Juice.shake(p, Juice.Shake.TINY)


## Puts everything back, however the state is left — including by a death, which is the one
## route that can arrive mid-burst.
##
## `_cooldown_left` survives on purpose, for the reason PlayerAttack's does: it is a property
## of the player, not of the machine's tenancy, so being pulled out of a roll must never be a
## way to refresh it. Cancelling a roll therefore costs the player the burst and buys them
## nothing, which is the right shape for an exploit — self-punishing rather than policed.
func exit() -> void:
	_time_left = 0.0
	_burst_left = 0.0
	_iframes_left = 0.0

	if _tween != null and _tween.is_valid():
		_tween.kill()
	_tween = null

	if p == null:
		return

	p.rolling_invulnerable = false
	if p.animated_sprite_2d != null:
		p.animated_sprite_2d.scale = Vector2.ONE


func is_committed() -> bool:
	return _time_left > 0.0


## The burst overrides the walk vector outright; the recovery roots the player.
##
## Rooting is not decoration — it is the debt half of the speed budget in the header. Letting
## the player walk out of the recovery makes sustained rolling strictly faster than walking
## again, which is the thing the whole design is arranged to prevent.
func movement_velocity(walk: Vector2) -> Vector2:
	if _burst_left > 0.0:
		return _direction * _speed
	if _time_left > 0.0:
		return Vector2.ZERO
	return walk


## Godot's own callback on this Node, NOT PlayerState's routed `process()` — the same split
## PlayerAttack documents at length. The cooldown and the i-frame timer both have to keep
## draining while the machine is parked in PlayerIdle, which the routed hook cannot do.
func _process(delta: float) -> void:
	if _cooldown_left > 0.0:
		_cooldown_left = maxf(0.0, _cooldown_left - delta)

	if _iframes_left > 0.0:
		_iframes_left = maxf(0.0, _iframes_left - delta)
		if _iframes_left <= 0.0 and p != null and is_instance_valid(p):
			p.rolling_invulnerable = false

	if _time_left <= 0.0:
		return
	# The roll's own progression only advances while the machine is actually running it;
	# exit() zeroes both timers, so this is belt and braces against a state pulled away
	# between frames.
	if fsm == null or fsm.state != self:
		return

	_burst_left = maxf(0.0, _burst_left - delta)
	_time_left = maxf(0.0, _time_left - delta)
	if _time_left <= 0.0:
		fsm.change_to("PlayerIdle")


func _start_squash() -> void:
	var sprite: Node2D = p.animated_sprite_2d
	if sprite == null:
		return

	if _tween != null and _tween.is_valid():
		_tween.kill()

	sprite.scale = Vector2.ONE
	# Created off the PLAYER, not off this state node: a Tween bound to a node is killed with
	# it, and binding it here would leave a live tween writing to the sprite after the state
	# had been torn down.
	_tween = p.create_tween()
	_tween.tween_property(sprite, "scale", ROLL_SQUASH, ROLL_TIME * ROLL_SQUASH_IN) \
		.set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)
	_tween.tween_property(sprite, "scale", Vector2.ONE, ROLL_TIME * (1.0 - ROLL_SQUASH_IN)) \
		.set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_IN)


## Which way a roll goes: where the player is already moving, or where they are facing when
## standing still.
##
## Reads the applied `velocity` rather than `Player.v`, and that is not interchangeable. `v`
## is the per-frame accumulator InputManager fills from `_physics_process` and
## `Player._process_movement()` zeroes at the end of every physics frame, while a dodge press
## arrives from `_input()` — so `v` is whatever the last frame happened to leave behind and is
## zero as often as not. `velocity` is the value that actually moved the player, which is also
## what `player.gd` derives the sprite's facing from, so the roll and the facing can never
## disagree about which way "forward" is.
##
## Pure and static so the standing-still case is testable without a player.
static func roll_direction(current_velocity: Vector2, facing_left: bool) -> Vector2:
	if current_velocity.length_squared() > 0.0:
		return current_velocity.normalized()
	return Vector2.LEFT if facing_left else Vector2.RIGHT


## How fast sustained rolling travels, as a multiple of just walking, over one full cycle of
## `cycle_seconds`. 1.0 means the two are exactly as fast as each other.
##
## The model is deliberately blunt and it is the same one the header states: burst at
## `speed_mult`, root through the recovery, walk through everything else. A cycle shorter than
## the roll plus its recovery is not a cycle the player can actually sustain, so it reports the
## roll alone rather than pretending the missing time was spent walking.
##
## Pure, because the invariant it encodes ("rolling is never faster than walking") is a
## statement about four constants and nothing else — no player, no frames, no tree.
static func sustained_speed_ratio(
		roll_time: float = ROLL_TIME,
		speed_mult: float = ROLL_SPEED_MULT,
		recovery: float = ROLL_RECOVERY,
		cycle_seconds: float = ROLL_COOLDOWN) -> float:
	if cycle_seconds <= 0.0:
		return 0.0

	var committed := roll_time + recovery
	var walking := maxf(0.0, cycle_seconds - committed)
	var distance := roll_time * speed_mult + walking
	return distance / maxf(cycle_seconds, committed)
