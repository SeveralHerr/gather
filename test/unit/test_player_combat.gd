extends RefCounted

## Covers the two things a sword swing and a dodge roll are made of: the rules that decide
## when each may start, and the timers that decide when each is over.
##
## **A live Player is out of reach here and always will be.** Half its @onready fields resolve
## `../../Systems` and `../../UI`, and `player.gd` says so outright above `build_payload`. So
## everything asserted below is either a pure static (`Player.hit_lands`,
## `Player.dodge_allowed`, `PlayerRoll.sustained_speed_ratio`, ...) or a bare state node with
## its timers set by hand and `_process` driven one tick at a time — which is exactly the
## seam those statics were factored out to expose.
##
## The four behaviours worth the file existing, in the order they broke:
##
##   1. a swing in its active frames cannot be stopped from outside the state machine. It used
##      to be: `Player._gather_input_release()` called `animation_player.stop()` on any gather
##      RELEASE, and on a phone gather and attack are the same physical button, so a tap on HIT
##      cut its own animation and `_physics_process` then disarmed the hitbox. Nothing errored
##      and the swing still looked like a swing — the enemy simply took no damage.
##   2. a press arriving during a swing is buffered, not dropped and not a restart.
##   3. the roll's i-frames actually stop a hit, through the flag PlayerRoll owns rather than
##      the one the respawn sequence owns.
##   4. rolling on repeat is never a faster way to travel than walking.
##
## Every assertion is on a value, never on "it did not error": a runtime error inside a
## `-> String` test still returns "" and counts as a pass (gather-1t9), so read the runner's
## stderr as well as its verdict.

const ATTACK_SCRIPT := "res://player/states/player_attack.gd"

var _T

var attack: PlayerState
var roll: PlayerRoll
var machine: StateMachine
var idle: PlayerState


func setup() -> void:
	# Never added to the tree. These states have no _ready() and the tests drive `_process`
	# by hand, which is the point — a state whose cadence only advances when Godot feels like
	# calling it is a cadence no test can pin.
	attack = load(ATTACK_SCRIPT).new()
	roll = PlayerRoll.new()
	machine = StateMachine.new()
	idle = PlayerState.new()


func teardown() -> void:
	for node in [attack, roll, machine, idle]:
		if node != null and is_instance_valid(node):
			node.free()
	attack = null
	roll = null
	machine = null
	idle = null


## Puts the attack state exactly where `_start_swing()` would, without the player it needs.
func _arm_swing(active: float = 0.2) -> void:
	attack.set("_active_left", active)
	attack.set("_cooldown_left", active + attack.SWING_RECOVERY)


func _active_left() -> float:
	return float(attack.get("_active_left"))


func _swing_cooldown() -> float:
	return float(attack.get("_cooldown_left"))


# --- the swing is atomic ------------------------------------------------------

func test_a_gather_release_cannot_stop_a_live_swing() -> String:
	# The reported bug in one line. On a phone `gather` and `attack` come off the same
	# contextual button (ui/mobile_controls.gd), so the release that ends a tap on HIT is a
	# `gather` release — and it used to run `animation_player.stop()` unconditionally.
	_arm_swing()

	return _T.assert_false(
		Player.release_may_stop_animation(attack),
		"a release arriving mid-swing is refused the AnimationPlayer")


func test_a_gather_release_still_stops_a_looping_gather_animation() -> String:
	# The other half, and the reason the line was not simply deleted: Gather and Gather_left
	# are authored `loop_mode = 1` in main.tscn, so they never end on their own. A guard that
	# refused every release would leave the pickaxe swinging for the rest of the session.
	var err: String = _T.assert_true(
		Player.release_may_stop_animation(idle), "an ordinary state still yields the stop")
	if err != "":
		return err

	# And a machine that has not readied yet, which is a real frame in every boot.
	return _T.assert_true(
		Player.release_may_stop_animation(null), "no state at all still yields the stop")


func test_the_swings_recovery_is_interruptible_even_though_its_active_frames_are_not() -> String:
	# owns_swing() is deliberately narrower than "the state is PlayerAttack". Once the blow has
	# landed there is nothing left for the atomicity rule to protect, and a combat system that
	# holds the player hostage through the follow-through punishes attacking at all.
	_arm_swing()
	attack._process(0.25)

	var err: String = _T.assert_false(attack.owns_swing(), "the active window has closed")
	if err != "":
		return err
	err = _T.assert_gt(_swing_cooldown(), 0.0, "but the cadence is still running")
	if err != "":
		return err
	return _T.assert_true(
		Player.release_may_stop_animation(attack), "a release during recovery is allowed")


func test_the_active_window_runs_on_its_own_clock_and_nothing_elses() -> String:
	# The window is timed from the animation's declared length in this state's own `_process`.
	# It deliberately does NOT read `AnimationPlayer.is_playing()` and connects to no
	# `animation_finished` — that signal belongs to a node this state does not own, fires for
	# whichever animation happens to be running, and is silent when another system plays over
	# the top. All three of those are how the swing used to end early.
	_arm_swing(0.2)

	var err: String = _T.assert_true(attack.owns_swing(), "the swing starts live")
	if err != "":
		return err

	attack._process(0.1)
	err = _T.assert_true(attack.owns_swing(), "half way through it is still live")
	if err != "":
		return err

	attack._process(0.1)
	return _T.assert_false(attack.owns_swing(), "and it closes on its own length, not early")


func test_the_player_is_slowed_but_not_rooted_mid_swing() -> String:
	# Not zero, on purpose. The swing is 0.2s and enemies lunge from 18px; a player pinned in
	# place every time they attack cannot back out of a fight they have misjudged, which is
	# most of the early game. Slowed reads as weight; rooted reads as a trap.
	_arm_swing()
	var walk := Vector2(50.0, 0.0)

	var moving: Vector2 = attack.movement_velocity(walk)
	var err: String = _T.assert_gt(moving.length(), 0.0, "the player can still retreat")
	if err != "":
		return err
	err = _T.assert_true(
		moving.length() < walk.length(), "but visibly slower than walking (%s)" % str(moving))
	if err != "":
		return err

	attack._process(0.25)
	return _T.assert_float_eq(
		attack.movement_velocity(walk).length(), walk.length(), 0.001,
		"full speed returns the moment the blow has landed")


# --- the input buffer ---------------------------------------------------------

func test_a_press_during_a_swing_waits_rather_than_firing_immediately() -> String:
	# Buffered, not dropped and not a restart. A bare `play()` would reset the swing that was
	# about to land, so holding the button produces a hitbox jittering at frame zero and an
	# enemy that is never hit at all.
	var AttackState = load(ATTACK_SCRIPT)

	return _T.assert_eq(
		AttackState.cadence_after(0.12, true, true), AttackState.Cadence.WAIT,
		"a buffered press does not jump the cadence")


func test_the_buffered_press_fires_the_instant_the_cadence_allows() -> String:
	# The reason to buffer at all: a player pressing in rhythm lands roughly every other press
	# 30ms before the recovery ends, and dropping those makes the sword feel like it is
	# ignoring them.
	var AttackState = load(ATTACK_SCRIPT)

	return _T.assert_eq(
		AttackState.cadence_after(0.0, true, true), AttackState.Cadence.SWING,
		"the follow-up swing is due")


func test_an_unbuffered_swing_hands_the_machine_back() -> String:
	var AttackState = load(ATTACK_SCRIPT)

	return _T.assert_eq(
		AttackState.cadence_after(0.0, false, true), AttackState.Cadence.FREE,
		"nothing queued, so the machine returns to PlayerIdle")


func test_a_buffered_press_that_outlived_its_state_is_dropped() -> String:
	# The machine moved on — the player started mining, or died. Firing the queued swing then
	# would produce a sword coming out of a gather half a second after the button was
	# released, which reads as the game acting on its own rather than as a late input.
	var AttackState = load(ATTACK_SCRIPT)

	return _T.assert_eq(
		AttackState.cadence_after(0.0, true, false), AttackState.Cadence.DROP,
		"a buffer whose state is gone is discarded")


func test_the_cadence_survives_being_pulled_out_of_the_state() -> String:
	# `exit()` deliberately does not clear the cooldown. If it did, "swing, tap gather, swing"
	# would be a way to attack as fast as the player can alternate two keys — the cadence is a
	# property of the arm, not of which state the machine happens to be parked in.
	_arm_swing()
	var before := _swing_cooldown()

	attack.exit()

	var err: String = _T.assert_float_eq(
		_active_left(), 0.0, 0.001, "leaving closes the active window")
	if err != "":
		return err
	return _T.assert_float_eq(
		_swing_cooldown(), before, 0.001, "but the cadence keeps running")


# --- the two-hit alternation --------------------------------------------------

func test_consecutive_swings_alternate() -> String:
	var AttackState = load(ATTACK_SCRIPT)

	var err: String = _T.assert_eq(
		AttackState._animation_for(false, 0), "Attack", "the first swing")
	if err != "":
		return err
	err = _T.assert_eq(
		AttackState._animation_for(false, 1), "Attack2", "the second swing is a different one")
	if err != "":
		return err
	# `_swing_index` only ever climbs, so the lookup has to wrap rather than index raw.
	err = _T.assert_eq(
		AttackState._animation_for(false, 2), "Attack", "and it wraps back round")
	if err != "":
		return err
	return _T.assert_eq(
		AttackState._animation_for(true, 1), "Attack_Left_2",
		"facing left picks from the left-hand pair")


func test_the_hitbox_is_authored_per_direction_so_the_swing_names_differ() -> String:
	# Facing is frozen mid-swing precisely because these are two different animations moving
	# the `Attack` area along two different paths. If the two facings ever named the same
	# animation, freezing the facing would be pointless and this test says so.
	var AttackState = load(ATTACK_SCRIPT)

	return _T.assert_false(
		AttackState._animation_for(false, 0) == AttackState._animation_for(true, 0),
		"left and right are different swings")


# --- one swing, one hit -------------------------------------------------------

func test_an_enemy_cannot_be_hit_twice_by_one_swing() -> String:
	# `body_entered` is not once-per-swing. The `Attack` area's position AND rotation are both
	# keyframed, so it genuinely leaves an enemy and arrives back on it inside one 0.2s
	# animation, and Godot reports every arrival. Against a stationary skeleton that is double
	# damage, invisible in every reading except the health bar emptying twice as fast as the
	# sword claims it should.
	var seen := {}

	var err: String = _T.assert_true(
		Player.register_swing_hit(seen, 101), "the first contact lands")
	if err != "":
		return err
	return _T.assert_false(
		Player.register_swing_hit(seen, 101), "the area sweeping back over it does not")


func test_a_new_swing_may_hit_the_same_enemy_again() -> String:
	# The dictionary is cleared at the START of each swing (PlayerAttack._start_swing calls
	# Player.begin_swing before arming the hitbox, never after — a clear that ran afterwards
	# would wipe a hit that had already landed on the first physics frame).
	var seen := {}
	Player.register_swing_hit(seen, 101)

	seen.clear()

	return _T.assert_true(
		Player.register_swing_hit(seen, 101), "the follow-up swing hits the same skeleton")


func test_two_enemies_in_one_swing_both_take_it() -> String:
	var seen := {}
	Player.register_swing_hit(seen, 101)

	return _T.assert_true(
		Player.register_swing_hit(seen, 202), "the guard is per enemy, not per swing")


# --- the roll's invulnerability ----------------------------------------------

func test_the_rolls_iframes_block_a_hit() -> String:
	# The whole point of the dodge. `rolling_invulnerable` is the flag PlayerRoll owns.
	return _T.assert_false(
		Player.hit_lands(false, false, true, false), "a hit during a roll does not land")


func test_an_ordinary_hit_still_lands() -> String:
	return _T.assert_true(
		Player.hit_lands(false, false, false, false), "nothing is blocking an ordinary hit")


func test_each_invulnerability_has_exactly_one_owner() -> String:
	# Four flags, four owners: the death sequence, the respawn grace, the roll, the debug
	# panel. The roll deliberately does NOT reuse `invulnerable` — `_grant_invulnerability()`
	# sets it, awaits, and clears it unconditionally, so sharing it breaks in both directions:
	# a respawn grace ending mid-roll would strip the roll's i-frames, and a roll ending inside
	# a respawn grace would strip the respawn's, killing a player who has just come back and is
	# still standing where they died.
	var flags := [
		["dead", Player.hit_lands(true, false, false, false)],
		["respawn grace", Player.hit_lands(false, true, false, false)],
		["rolling", Player.hit_lands(false, false, true, false)],
		["god mode", Player.hit_lands(false, false, false, true)],
	]

	for entry in flags:
		var err: String = _T.assert_false(
			bool(entry[1]), "'%s' alone is enough to stop a hit" % str(entry[0]))
		if err != "":
			return err

	return ""


func test_the_iframes_cover_the_burst_but_not_the_recovery() -> String:
	# A dodge that is invulnerable for exactly as long as it moves has to be timed to the
	# frame, which is not a thing to ask of a child on a phone — hence the small tail. But the
	# recovery has to be a genuine exposure, or the roll is a half-second of free safety.
	var err: String = _T.assert_gte(
		PlayerRoll.ROLL_IFRAME_TIME, PlayerRoll.ROLL_TIME,
		"the whole burst is covered")
	if err != "":
		return err
	return _T.assert_true(
		PlayerRoll.ROLL_IFRAME_TIME < PlayerRoll.ROLL_TIME + PlayerRoll.ROLL_RECOVERY,
		"the recovery is not")


# --- the roll's cooldown and speed budget ------------------------------------

func test_a_fresh_roll_state_is_ready() -> String:
	return _T.assert_true(roll.can_roll(), "nothing has been spent yet")


func test_the_cooldown_drains_on_a_clock_that_runs_while_another_state_is_current() -> String:
	# PlayerRoll._process is GODOT's callback on the node, not PlayerState's routed `process()`
	# — the state nodes are real children of Player/StateMachine, so it ticks every frame
	# whether or not the machine is pointing here. It has to: the cooldown is spent while the
	# player is walking around in PlayerIdle, and the routed hook does not run then.
	roll.set("_cooldown_left", PlayerRoll.ROLL_COOLDOWN)

	var err: String = _T.assert_false(roll.can_roll(), "a spent roll is on cooldown")
	if err != "":
		return err

	roll._process(PlayerRoll.ROLL_COOLDOWN * 0.5)
	err = _T.assert_false(roll.can_roll(), "half way through it is still on cooldown")
	if err != "":
		return err

	roll._process(PlayerRoll.ROLL_COOLDOWN)
	return _T.assert_true(roll.can_roll(), "and it comes back")


func test_cancelling_a_roll_does_not_refresh_its_cooldown() -> String:
	# exit() deliberately leaves `_cooldown_left` alone, for the same reason the swing's
	# cadence survives: being pulled out of a roll must never be a way to get another one
	# sooner. Cancelling therefore costs the player the burst and buys them nothing, which is
	# the right shape for an exploit — self-punishing rather than policed.
	roll.set("_cooldown_left", PlayerRoll.ROLL_COOLDOWN)
	roll.set("_time_left", PlayerRoll.ROLL_TIME)

	roll.exit()

	var err: String = _T.assert_float_eq(
		float(roll.get("_cooldown_left")), PlayerRoll.ROLL_COOLDOWN, 0.001,
		"the cooldown is untouched")
	if err != "":
		return err
	return _T.assert_false(roll.is_committed(), "but the roll itself is over")


func test_the_cooldown_outlasts_the_roll_it_gates() -> String:
	# Otherwise the state releases the player straight into another roll and the recovery
	# stops being a recovery at all.
	return _T.assert_gt(
		PlayerRoll.ROLL_COOLDOWN, PlayerRoll.ROLL_TIME + PlayerRoll.ROLL_RECOVERY,
		"there is real downtime between rolls")


func test_a_roll_covers_more_ground_than_walking_for_its_duration() -> String:
	# The half that makes it worth pressing: it has to actually get the player out of the way,
	# and `enemy.gd`'s lunge reaches 18px.
	var rolled := PlayerRoll.ROLL_TIME * PlayerRoll.ROLL_SPEED_MULT * Player.MOVE_SPEED
	var walked := PlayerRoll.ROLL_TIME * Player.MOVE_SPEED

	var err: String = _T.assert_gt(rolled, walked, "a roll outruns a walk over its own 0.25s")
	if err != "":
		return err
	return _T.assert_gt(rolled, 18.0, "and clears an enemy's lunge (%.1fpx)" % rolled)


func test_sustained_rolling_is_never_faster_than_walking() -> String:
	# THE invariant of the roll's tuning, and the one a retune is most likely to break by
	# accident. If rolling on repeat outran walking, the roll would stop being a defensive
	# option and become the way the player crosses the island — which is both worse to play
	# and worse to watch.
	var ratio: float = PlayerRoll.sustained_speed_ratio()

	return _T.assert_true(
		ratio <= 1.0 + 0.001,
		"rolling on repeat travels at %.3fx walking" % ratio)


func test_a_longer_cooldown_cannot_be_what_enforces_that() -> String:
	# The part that is easy to get wrong. Whatever the player is not rolling through they are
	# WALKING through, so a longer cooldown only adds neutral time to the cycle — it leaves
	# the per-roll surplus exactly where it was. Only the rooted recovery can pay it back,
	# which is why ROLL_RECOVERY is derived from the other two constants rather than tuned.
	var tight: float = PlayerRoll.sustained_speed_ratio(
		PlayerRoll.ROLL_TIME, PlayerRoll.ROLL_SPEED_MULT, PlayerRoll.ROLL_RECOVERY,
		PlayerRoll.ROLL_TIME + PlayerRoll.ROLL_RECOVERY)
	var loose: float = PlayerRoll.sustained_speed_ratio(
		PlayerRoll.ROLL_TIME, PlayerRoll.ROLL_SPEED_MULT, PlayerRoll.ROLL_RECOVERY, 10.0)

	return _T.assert_float_eq(
		tight, loose, 0.001,
		"the cycle length does not move the ratio (%.3f vs %.3f)" % [tight, loose])


func test_halving_the_recovery_would_make_rolling_the_fastest_travel_in_the_game() -> String:
	# The negative case, so the test above cannot pass by the arithmetic being trivially
	# capped. This is what the constants would buy if someone shortened the recovery for feel.
	var ratio: float = PlayerRoll.sustained_speed_ratio(
		PlayerRoll.ROLL_TIME, PlayerRoll.ROLL_SPEED_MULT, PlayerRoll.ROLL_RECOVERY * 0.5,
		PlayerRoll.ROLL_COOLDOWN)

	return _T.assert_gt(ratio, 1.0, "a shorter recovery really would outrun walking")


# --- the roll's movement and direction ---------------------------------------

func test_a_roll_goes_where_the_player_is_already_moving() -> String:
	var direction := PlayerRoll.roll_direction(Vector2(0.0, 40.0), false)

	return _T.assert_float_eq(
		direction.y, 1.0, 0.001, "rolling downwards while walking downwards (%s)" % str(direction))


func test_a_standing_player_rolls_the_way_they_are_facing() -> String:
	# Reads the applied `velocity` rather than `Player.v`: `v` is the per-frame accumulator
	# InputManager fills and `_process_movement()` zeroes every physics frame, while a dodge
	# press arrives from `_input()` — so `v` is zero as often as not. `velocity` is also what
	# the sprite's facing is derived from, so the roll and the facing cannot disagree.
	var err: String = _T.assert_eq(
		PlayerRoll.roll_direction(Vector2.ZERO, true), Vector2.LEFT, "facing left rolls left")
	if err != "":
		return err
	return _T.assert_eq(
		PlayerRoll.roll_direction(Vector2.ZERO, false), Vector2.RIGHT, "and right rolls right")


func test_the_burst_ignores_the_walk_input_entirely() -> String:
	# A roll the player can steer mid-flight is a dash, and a dash with i-frames is a strictly
	# better walk. The direction is committed at the press.
	roll.set("_burst_left", PlayerRoll.ROLL_TIME)
	roll.set("_time_left", PlayerRoll.ROLL_TIME + PlayerRoll.ROLL_RECOVERY)
	roll.set("_direction", Vector2.RIGHT)
	roll.set("_speed", 110.0)

	var against: Vector2 = roll.movement_velocity(Vector2(-50.0, 0.0))

	return _T.assert_float_eq(
		against.x, 110.0, 0.001, "pushing the other way changes nothing (%s)" % str(against))


func test_the_recovery_roots_the_player() -> String:
	# The debt half of the speed budget above. Letting the player walk out of the recovery
	# makes sustained rolling strictly faster than walking again, which is the whole thing the
	# tuning is arranged to prevent.
	roll.set("_burst_left", 0.0)
	roll.set("_time_left", PlayerRoll.ROLL_RECOVERY)

	return _T.assert_eq(
		roll.movement_velocity(Vector2(50.0, 0.0)), Vector2.ZERO, "the recovery cannot be walked out of")


func test_an_idle_roll_state_leaves_walking_alone() -> String:
	var walk := Vector2(50.0, -50.0)

	return _T.assert_eq(
		roll.movement_velocity(walk), walk, "a state that is not rolling changes nothing")


# --- when a dodge is allowed --------------------------------------------------

func test_a_dodge_is_refused_out_of_a_live_swing() -> String:
	_arm_swing()

	return _T.assert_false(
		Player.dodge_allowed(attack, true, false, false),
		"the blow is mid-flight and cancelling it would take the damage off it")


func test_a_dodge_is_allowed_out_of_a_swings_recovery() -> String:
	# Deliberate, and the reason `owns_swing()` is narrower than "the state is PlayerAttack".
	_arm_swing()
	attack._process(0.25)

	return _T.assert_true(
		Player.dodge_allowed(attack, true, false, false),
		"once the hit has landed the player may leave")


func test_a_dodge_cannot_cancel_a_dodge() -> String:
	roll.set("_time_left", PlayerRoll.ROLL_TIME)

	return _T.assert_false(
		Player.dodge_allowed(roll, true, false, false), "a roll is a commitment")


func test_a_dodge_is_refused_while_dead_or_mid_respawn() -> String:
	# `disable_input` covers the half-second death-and-respawn window as well as an open
	# panel. Rolling through it would mean rolling away from the spawn point the respawn is
	# about to teleport the player back to.
	var err: String = _T.assert_false(
		Player.dodge_allowed(idle, true, true, false), "the dead do not roll")
	if err != "":
		return err
	return _T.assert_false(
		Player.dodge_allowed(idle, true, false, true), "nor does a player mid-respawn")


func test_a_dodge_is_refused_on_cooldown() -> String:
	return _T.assert_false(
		Player.dodge_allowed(idle, false, false, false), "the cooldown is honoured")


func test_an_ordinary_dodge_is_allowed() -> String:
	# The guard must not swallow the input it exists to gate.
	return _T.assert_true(
		Player.dodge_allowed(idle, true, false, false), "walking along, dodge available")
