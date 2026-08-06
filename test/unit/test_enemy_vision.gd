extends RefCounted

## Covers the line-of-sight gate on the hunt, the grace period on losing it, and the sidestep's
## new wall-derived direction.
##
## ## Why every assertion here is against a static function
##
## The bug this feature fixes is a player standing inside a walled house with skeletons pressed
## against the outside of the wall, and the thing that makes it a bug is a *wall* — which is a
## tilemap collision polygon in a live physics world. Headless pumps no physics, so the honest
## options are to assert nothing, or to move every decision out of the raycast and into a pure
## function and assert those. The raycast itself is four lines with no branches worth testing;
## the decisions built on top of it are where the sign errors, the inverted conditions and the
## forgotten raider exemption live, and every one of them is asserted below.
##
## The one thing that CANNOT be covered here is that bit 7 of the tileset actually carries a
## polygon for every wall and door tile. That is a resource, not a decision, and it is verified
## at runtime.

var _T


# --- the hunt gate -----------------------------------------------------------


func test_a_wall_between_them_stops_an_ambient_chase() -> String:
	# The whole feature in one assertion. Same distance, same ranges, one bit of difference.
	var seen: bool = EnemyIdle.should_hunt(20.0, 30.0, 5.0, false, true)
	var err: String = _T.assert_true(seen, "an ambient enemy chases a player it can see")
	if err != "":
		return err

	return _T.assert_false(EnemyIdle.should_hunt(20.0, 30.0, 5.0, false, false),
		"and does not chase the same player through a wall")


func test_distance_still_gates_before_line_of_sight_does() -> String:
	# Sight is necessary, never sufficient. A player in clear view across the island is still not
	# an ambient enemy's business — `hunt_range` is 30px for a reason, and a gate that answered
	# "can see" instead of "can see AND is near" would turn every wanderer into a raider.
	var err: String = _T.assert_false(EnemyIdle.should_hunt(200.0, 30.0, 5.0, false, true),
		"clear line of sight from across the island is still out of range")
	if err != "":
		return err

	# And the inner edge: inside the attack band the follow state is the wrong answer, which is
	# what the `> attack_range` half of the original condition was for.
	return _T.assert_false(EnemyIdle.should_hunt(4.0, 30.0, 5.0, false, true),
		"a player already inside attack range is not something to start walking toward")


func test_the_band_boundaries_are_exclusive_at_both_ends() -> String:
	# Pinned because the original condition was `< hunt_range and > attack_range` and a later
	# tidy-up to `<=` on the outer edge would make an enemy chase from exactly its own range —
	# harmless — while the same tidy-up on the inner edge makes it oscillate between follow and
	# attack on the boundary, which is a visible stutter nobody would trace back here.
	var err: String = _T.assert_false(EnemyIdle.in_hunt_band(30.0, 30.0, 5.0),
		"exactly at hunt_range is out")
	if err != "":
		return err
	return _T.assert_false(EnemyIdle.in_hunt_band(5.0, 30.0, 5.0), "exactly at attack_range is out")


# --- the raider exemption ----------------------------------------------------


func test_a_raider_hunts_through_walls_and_an_ambient_skeleton_does_not() -> String:
	# The single most surprising line in the feature, so it is the one most worth pinning. A
	# raider that gave up because the player stepped behind a wall is a raid that never clears:
	# RaidDirector counts live raiders and pays only on zero, so the banner would hang until dawn
	# with enemies standing still across the island.
	var err: String = _T.assert_true(
		Enemy.hunts_through_walls_for(EnemyRegistry.RAIDER_BONE, false),
		"a raider comes for you regardless of what you built")
	if err != "":
		return err

	return _T.assert_false(Enemy.hunts_through_walls_for(EnemyRegistry.BONE, false),
		"an ambient skeleton respects a wall")


func test_the_exemption_is_derived_from_the_registry_and_cannot_drift() -> String:
	# Derived from EnemyRegistry.RAIDER_TYPES rather than restated, so a raider type added later
	# is exempt for free. This asserts that relationship rather than the two types that exist
	# today — the point is that there is no second list to forget.
	for type in EnemyRegistry.RAIDER_TYPES:
		if not Enemy.hunts_through_walls_for(type, false):
			return _T.assert_true(false, "raider type '%s' respects walls and would strand a raid" % type)

	# And nothing else is exempt by accident. The elite is the interesting one: it is a bone enemy
	# underneath and is the only other enemy placed rather than trickled in, so a rule written
	# about "special enemies" instead of about raiders would sweep it up.
	for type in [EnemyRegistry.BONE, EnemyRegistry.SPIDER, EnemyRegistry.ELITE, EnemyRegistry.CHARGED]:
		if Enemy.hunts_through_walls_for(type, false):
			return _T.assert_true(false, "'%s' hunts through walls and should not" % type)

	return ""


func test_a_scene_can_opt_out_without_being_a_raider() -> String:
	# The @export exists so a future enemy scene can ignore walls without a code change. It is
	# deliberately the *second* route rather than the only one — see the long comment on
	# Enemy.hunts_through_walls_for for why raiders do not use it.
	return _T.assert_true(Enemy.hunts_through_walls_for(EnemyRegistry.BONE, true),
		"the exported flag is honoured for a type the registry says nothing special about")


# --- the grace period --------------------------------------------------------


func test_a_chase_survives_a_moment_out_of_sight() -> String:
	# An enemy that drops the chase on the frame the player steps behind cover does not read as
	# stealth, it reads as the AI switching off. This is the assertion that stops someone
	# "simplifying" the grace away by reusing the idle gate here.
	var err: String = _T.assert_false(
		EnemyFollow.should_give_up(0.0, EnemyFollow.GIVE_UP_AFTER, false),
		"losing sight this frame does not end the chase")
	if err != "":
		return err

	err = _T.assert_false(
		EnemyFollow.should_give_up(EnemyFollow.GIVE_UP_AFTER - 0.1, EnemyFollow.GIVE_UP_AFTER, false),
		"and neither does losing it a moment ago")
	if err != "":
		return err

	return _T.assert_true(
		EnemyFollow.should_give_up(EnemyFollow.GIVE_UP_AFTER, EnemyFollow.GIVE_UP_AFTER, false),
		"but the grace does expire, or a lost chase never ends")


func test_the_grace_is_long_enough_to_be_a_search_and_short_enough_to_end() -> String:
	# Bounds rather than the value, so retuning is free and deleting the behaviour is not. Under
	# a second is indistinguishable from giving up instantly; over five and an enemy that cannot
	# see you shadows you across the island, which is the original bug wearing a delay.
	var err: String = _T.assert_gte(EnemyFollow.GIVE_UP_AFTER, 1.0,
		"the enemy walks to where it last saw the player before losing interest")
	if err != "":
		return err
	return _T.assert_true(EnemyFollow.GIVE_UP_AFTER <= 5.0,
		"but it does lose interest inside the time a player would call it stalking")


func test_a_raider_chase_never_expires() -> String:
	# The other half of the exemption. Short-circuited rather than given an enormous grace, so
	# there is no expiry to get wrong rather than one set to a number that looks like infinity.
	return _T.assert_false(EnemyFollow.should_give_up(9999.0, EnemyFollow.GIVE_UP_AFTER, true),
		"a raider has not given up after an hour of no line of sight")


# --- the throttle ------------------------------------------------------------


func test_the_stagger_spreads_checks_across_the_period_and_never_past_it() -> String:
	# The offset is what stops a raid's worth of enemies raycasting on the same physics tick. It
	# must stay inside [0, period): an offset of a full period would delay an enemy's first
	# check by longer than the throttle it belongs to, which reads as one enemy in the group
	# being asleep.
	var period := 0.3
	var offsets := {}
	for id in [1, 2, 3, 101, 5417, 993, 1000, 1001]:
		var offset := Enemy.los_stagger_offset(id, period)
		if offset < 0.0 or offset >= period:
			return _T.assert_true(false, "id %d offsets %f, outside [0, %f)" % [id, offset, period])
		offsets[offset] = true

	# Not all identical — the entire point. Ids 1000 and 1001 are in the list because the
	# implementation takes a modulo, and a modulo with the wrong base collapses whole runs of ids
	# onto one value without ever leaving the legal range.
	var err: String = _T.assert_gt(offsets.size(), 4, "different enemies get different phases")
	if err != "":
		return err

	# A negative instance id (never produced by Godot, but this is arithmetic on an int) must not
	# hand back a negative cooldown, which would fire the check every frame forever.
	err = _T.assert_gte(Enemy.los_stagger_offset(-7, period), 0.0, "a negative id still offsets forward")
	if err != "":
		return err

	# Disabling the throttle asks for every frame rather than for a division by zero.
	return _T.assert_float_eq(Enemy.los_stagger_offset(12345, 0.0), 0.0, 0.001,
		"a zero period is answered, not divided by")


func test_the_same_enemy_keeps_its_phase() -> String:
	# Derived from the instance id rather than rolled, so an enemy holds one phase for its whole
	# life. A re-rolled offset would let a group that re-enters range together re-cluster onto the
	# same tick, which is the thing the stagger exists to prevent.
	return _T.assert_float_eq(Enemy.los_stagger_offset(4242, 0.3),
		Enemy.los_stagger_offset(4242, 0.3), 0.001, "one enemy, one phase")


# --- the sidestep ------------------------------------------------------------


## What enemy_follow.physics_update does with the sign, so these tests assert the direction the
## enemy actually moves rather than the sign in isolation. The 0.35 is the mix-back constant in
## that function — a literal there, restated here on purpose: if the two drift, this test fails
## and points at the drift.
func _steer(dir: Vector2, sign_value: float) -> Vector2:
	return (dir.orthogonal() * sign_value + dir * 0.35).normalized()


func test_the_sidestep_slides_along_the_wall_toward_the_target() -> String:
	# The improvement over the coin flip. An enemy heading down-and-right into a wall on its right
	# should slide DOWN it — the direction that keeps most of the heading it wanted — rather than
	# have a 50% chance of walking back up and away from the player.
	var dir := Vector2(1, 1).normalized()
	var wall_normal := Vector2(-1, 0)  # a vertical wall to the right, facing back at the enemy

	var sign_value := EnemyFollow.sidestep_sign_for(dir, wall_normal, 1.0)
	var steering := _steer(dir, sign_value)

	# The useful way along the wall, derived independently of the function under test: the wall's
	# tangent, oriented toward where we wanted to go. Written this way rather than as a hardcoded
	# vector so the assertion does not silently encode Vector2.orthogonal()'s handedness.
	var tangent := wall_normal.orthogonal()
	var useful := tangent * signf(dir.dot(tangent))

	return _T.assert_gt(steering.dot(useful), 0.0,
		"the enemy slides along the wall in the direction it was trying to go")


func test_the_sidestep_direction_is_deterministic_for_a_given_contact() -> String:
	# The point of reading the normal at all. The old sign was re-rolled per episode, so an enemy
	# could pick the wrong way twice in a row; a contact-derived sign gives the same answer every
	# time the same corner is met, which is what makes two or three sidesteps clear a house.
	var dir := Vector2(1, 1).normalized()
	var wall_normal := Vector2(-1, 0)

	# Called with OPPOSITE fallbacks. If the fallback leaks into the answer these disagree.
	var a := EnemyFollow.sidestep_sign_for(dir, wall_normal, 1.0)
	var b := EnemyFollow.sidestep_sign_for(dir, wall_normal, -1.0)

	var err: String = _T.assert_float_eq(a, b, 0.001, "the wall decides, not the coin")
	if err != "":
		return err
	return _T.assert_true(absf(a) == 1.0, "and it decides one of the two directions, not zero")


func test_a_head_on_wall_hands_the_decision_back() -> String:
	# Square into a flat wall, both ways along it are exactly as good, and the contact genuinely
	# has nothing to say. The fallback matters here rather than being a formality: a formula that
	# picked a side anyway would pick the SAME side every time for a given approach, so an enemy
	# would grind into one corner of a house forever — worse than the coin flip it replaced,
	# because it is deterministic.
	var dir := Vector2(1, 0)
	var wall_normal := Vector2(-1, 0)

	var err: String = _T.assert_float_eq(EnemyFollow.sidestep_sign_for(dir, wall_normal, 1.0), 1.0, 0.001,
		"head-on, the caller's coin stands")
	if err != "":
		return err
	return _T.assert_float_eq(EnemyFollow.sidestep_sign_for(dir, wall_normal, -1.0), -1.0, 0.001,
		"either way it lands")


func test_a_contact_we_are_not_walking_into_is_ignored() -> String:
	# `_blocking_normal` returns zero when nothing was hit — an enemy jammed between two other
	# enemies rather than against a wall — and a normal we are moving AWAY from is not what
	# stopped us. Steering off either would send the enemy somewhere unrelated to the obstacle.
	var dir := Vector2(1, 0)

	var err: String = _T.assert_float_eq(EnemyFollow.sidestep_sign_for(dir, Vector2.ZERO, -1.0), -1.0, 0.001,
		"no contact, no opinion")
	if err != "":
		return err
	err = _T.assert_float_eq(EnemyFollow.sidestep_sign_for(dir, Vector2(1, 0), -1.0), -1.0, 0.001,
		"a face pointing the same way we are going is not what blocked us")
	if err != "":
		return err
	return _T.assert_float_eq(EnemyFollow.sidestep_sign_for(Vector2.ZERO, Vector2(-1, 0), 1.0), 1.0, 0.001,
		"and a zero heading has no orthogonal to pick between")
