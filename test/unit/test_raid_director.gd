extends RefCounted

## Covers the raid escalation curve and the director's save round-trip.
##
## The curve is entirely static, so most of this needs no SceneTree — the same shape as
## test_world_clock.gd, and for the same reason: a model that draws nothing can be asked
## questions without a viewport.
##
## What the curve tests are actually protecting is not any single number but the *shape*. A
## difficulty ramp is the classic thing that is retuned by nudging one constant and is wrong in
## a way nobody notices for months, because every individual night still looks plausible. So the
## assertions below are mostly relational — no night is easier than the night before it, the
## first raid is survivable, the ceiling is reached and then held — and only a couple pin an
## actual value.

var _T


# --- which nights raid --------------------------------------------------------


func test_the_first_nights_are_quiet() -> String:
	# A new player needs to have seen a night, built something and found the hotbar before the
	# game asks them to defend any of it.
	for day in range(1, RaidDirector.FIRST_RAID_NIGHT):
		var err: String = _T.assert_false(
			RaidDirector.raids_on_night(day), "night %d does not raid" % day)
		if err != "":
			return err

		var size_err: String = _T.assert_eq(
			RaidDirector.size_for_day(day), 0, "a quiet night sends nobody (day %d)" % day)
		if size_err != "":
			return size_err

	return _T.assert_true(
		RaidDirector.raids_on_night(RaidDirector.FIRST_RAID_NIGHT),
		"the first raid night raids")


func test_every_night_from_the_first_raid_night_raids() -> String:
	# Raids are nightly rather than periodic. A player who loses a night has to have the next
	# one to win back, and a gap would make the escalation read as random.
	for day in range(RaidDirector.FIRST_RAID_NIGHT, RaidDirector.FIRST_RAID_NIGHT + 20):
		var err: String = _T.assert_true(
			RaidDirector.raids_on_night(day), "night %d raids" % day)
		if err != "":
			return err
	return ""


# --- the size curve -----------------------------------------------------------


func test_the_first_raid_is_the_smallest_one() -> String:
	return _T.assert_eq(
		RaidDirector.size_for_day(RaidDirector.FIRST_RAID_NIGHT),
		RaidDirector.BASE_SIZE,
		"the opening raid is BASE_SIZE")


## The invariant that actually matters, and the one a retune breaks silently: a later night must
## never send fewer raiders than an earlier one. Any curve that dips is a difficulty setting that
## gets EASIER as the player gets stronger, and no single night's number would look wrong.
func test_no_night_is_easier_than_the_night_before_it() -> String:
	var previous := 0
	for day in range(1, 120):
		var size := RaidDirector.size_for_day(day)
		var err: String = _T.assert_gte(
			float(size), float(previous),
			"night %d sends at least as many as night %d (%d vs %d)" % [day, day - 1, size, previous])
		if err != "":
			return err
		previous = size
	return ""


func test_the_size_curve_reaches_its_ceiling_and_holds_it() -> String:
	# Unbounded growth is a frame-rate bug rather than a difficulty one — raiders are spawned
	# OUTSIDE EnemySpawner's population cap, deliberately, so nothing else bounds them.
	var late := RaidDirector.size_for_day(500)
	var err: String = _T.assert_eq(
		late, RaidDirector.MAX_SIZE, "a very late night is capped at MAX_SIZE")
	if err != "":
		return err

	# ...and the cap is reached from below rather than being the value the whole time.
	return _T.assert_true(
		RaidDirector.size_for_day(RaidDirector.FIRST_RAID_NIGHT) < RaidDirector.MAX_SIZE,
		"the opening raid is under the cap, so the ramp has somewhere to go")


## The ramp has to be felt within a session. A curve that technically grows but takes forty
## nights to add a raider is one the player experiences as flat — and a day is ten minutes, so
## forty nights is nearly seven hours.
func test_the_ramp_is_felt_within_a_few_nights() -> String:
	var opening := RaidDirector.size_for_day(RaidDirector.FIRST_RAID_NIGHT)
	var five_nights_later := RaidDirector.size_for_day(RaidDirector.FIRST_RAID_NIGHT + 5)
	return _T.assert_gte(
		float(five_nights_later), float(opening + 2),
		"five nights on, the raid is at least two raiders bigger (%d -> %d)"
			% [opening, five_nights_later])


# --- the health curve ---------------------------------------------------------


func test_a_quiet_night_scales_nothing() -> String:
	return _T.assert_float_eq(
		RaidDirector.health_mult_for_day(1), 1.0, 0.001,
		"a night with no raid has no multiplier to apply")


func test_raider_health_grows_and_then_stops() -> String:
	var first := RaidDirector.health_mult_for_day(RaidDirector.FIRST_RAID_NIGHT)
	var err: String = _T.assert_float_eq(
		first, 1.0, 0.001, "the opening raid is stock-health enemies")
	if err != "":
		return err

	var later := RaidDirector.health_mult_for_day(RaidDirector.FIRST_RAID_NIGHT + 10)
	var grew: String = _T.assert_gt(later, first, "ten nights on, raiders are tougher")
	if grew != "":
		return grew

	return _T.assert_float_eq(
		RaidDirector.health_mult_for_day(9999), RaidDirector.MAX_HEALTH_MULT, 0.001,
		"the health curve is capped")


## Health is what scales, and damage is deliberately left alone — the game has no armour, so a
## raider that hits harder every night is a difficulty setting the player has no dial to answer.
## This pins the ceiling somewhere a fight is still winnable: a stock skeleton is 10 health and
## the starting sword is not the one the player has by night 15.
func test_the_health_ceiling_stays_in_reach_of_a_sword() -> String:
	return _T.assert_true(
		RaidDirector.MAX_HEALTH_MULT <= 3.0,
		"a fully scaled raider is at most 3x a stock one (got %.2f)" % RaidDirector.MAX_HEALTH_MULT)


# --- the reward ---------------------------------------------------------------


func test_the_clear_bonus_scales_with_the_raid() -> String:
	var small := RaidDirector.reward_for_size(3)
	var large := RaidDirector.reward_for_size(12)
	var err: String = _T.assert_gt(
		float(large), float(small), "a bigger raid pays more to clear")
	if err != "":
		return err

	# A raid that sent nobody cannot pay. Guards against a "cleared" emitted for a night that
	# never opened one.
	return _T.assert_eq(RaidDirector.reward_for_size(0), 0, "no raid, no bonus")


## Priced against LandManager's curve rather than against taste. Twelve parcels cost ~3795 coins
## in total; a full run of raids has to be a visible contribution to that without being an
## alternative to mining gold, which is what the land economy is actually built on.
##
## The ceiling came down from 5000 with COST_GROWTH. 5000 was below the old ~6955 curve; against
## today's it is larger than the entire land economy, so the assertion could no longer fail for
## the reason it names. 1900 is half the map, which is what "not most of the land curve" has
## always meant — twenty nights of clears pay 1416, so the guard still has room to be right
## about the current numbers and teeth against a payout retune.
func test_a_run_of_raids_is_worth_land_but_is_not_the_land_economy() -> String:
	var total := 0
	for day in range(RaidDirector.FIRST_RAID_NIGHT, RaidDirector.FIRST_RAID_NIGHT + 20):
		total += RaidDirector.reward_for_size(RaidDirector.size_for_day(day))

	var err: String = _T.assert_gt(
		float(total), 500.0,
		"twenty nights of clears is worth several parcels (got %d coins)" % total)
	if err != "":
		return err

	return _T.assert_true(
		total < 1900,
		"...and is not most of the %d-coin land curve (got %d)" % [3795, total])


# --- save fidelity ------------------------------------------------------------


## The director is a Node, and `saveObject()` calls `get_path()`, so these tests need it
## actually parented — a detached node returns an empty path and pushes an error, which the
## runner reports as stderr noise rather than as a failure.
func _director() -> RaidDirector:
	var tree: SceneTree = Engine.get_main_loop() as SceneTree
	var director := RaidDirector.new()
	# Nothing may open a raid underneath a test that is setting state by hand.
	director.running = false
	tree.root.add_child(director)
	return director


func _drop(director: RaidDirector) -> void:
	var tree: SceneTree = Engine.get_main_loop() as SceneTree
	tree.root.remove_child(director)
	director.free()


## The failure this exists for is the one the save-fidelity section of CLAUDE.md describes: a
## load that succeeds and quietly hands the player back less than they had. A player four
## raiders into an eight-raider night who quicksaves is owed four more raiders and the part of
## the stagger they have already waited through — not a fresh raid and not none.
func test_a_raid_in_progress_survives_a_round_trip() -> String:
	var director := _director()
	director.raid_active = true
	director.raid_day = 9
	director.raid_size = 8
	director.raiders_pending = 4
	director._spawn_cooldown = 0.7
	director.last_raid_day = 9
	director.raids_cleared = 3

	var payload := director.saveObject()

	var restored := _director()
	restored.loadObject(payload)

	var checks := [
		[restored.raid_active, true, "the raid is still running"],
		[restored.raid_day, 9, "it is still night 9's raid"],
		[restored.raid_size, 8, "it is still an eight-raider night"],
		[restored.raiders_pending, 4, "four raiders are still owed"],
		[restored.last_raid_day, 9, "night 9 is still spent"],
		[restored.raids_cleared, 3, "the clear count carried"],
	]

	for check in checks:
		var err: String = _T.assert_eq(check[0], check[1], check[2])
		if err != "":
			_drop(director)
			_drop(restored)
			return err

	var cooldown_err: String = _T.assert_float_eq(
		restored._spawn_cooldown, 0.7, 0.001,
		"the wait for the next raider is progress and carried over")

	_drop(director)
	_drop(restored)
	return cooldown_err


## `last_raid_day` is what stops a load into the middle of a fought night opening a second raid
## on it. Without it a player who saves at 3am and reloads gets the whole night again, doubled.
func test_a_night_already_fought_cannot_raid_twice() -> String:
	var director := _director()
	director.last_raid_day = 7

	# The guard lives in _on_night_started, so drive that rather than start_raid — start_raid is
	# the deliberate override devtools uses and is allowed to re-open a night.
	director.running = true
	director._on_night_started(7)

	var err: String = _T.assert_false(
		director.raid_active, "night 7 does not raid a second time")

	_drop(director)
	return err


func test_a_save_written_before_raids_existed_loads_quietly() -> String:
	# Such a file has no entry for this node at all, but a hand-edited or partial one can reach
	# loadObject with an empty dictionary. Every read is `get` with a default precisely so this
	# is a no-op rather than a raise — and a raise inside `-> void` aborts the method and looks
	# exactly like success.
	var director := _director()
	director.loadObject({})

	var checks := [
		[director.raid_active, false, "no raid is running"],
		[director.raiders_pending, 0, "nobody is owed"],
		[director.raids_cleared, 0, "no raids have been cleared"],
	]

	for check in checks:
		var err: String = _T.assert_eq(check[0], check[1], check[2])
		if err != "":
			_drop(director)
			return err

	_drop(director)
	return ""


## A payload claiming an active raid with no size is a half-state this build cannot draw or
## finish: `raid_size` is what the banner counts against and what a clear tests, so a zero would
## be a raid that never ends. It is treated as over rather than carried forward.
func test_an_active_raid_with_no_size_is_treated_as_over() -> String:
	var director := _director()
	director.loadObject({"raid_active": true, "raid_size": 0, "raiders_pending": 5})

	var err: String = _T.assert_false(director.raid_active, "the half-state raid is closed")
	if err != "":
		_drop(director)
		return err

	var pending: String = _T.assert_eq(director.raiders_pending, 0, "and owes nobody")
	_drop(director)
	return pending


## `typeof(x) == TYPE_BOOL` rather than `x == true`, because comparing a String to a bool raises
## instead of evaluating false — and a raise here aborts loadObject and leaves every field below
## it at its constructor value.
func test_a_non_bool_active_flag_does_not_raise() -> String:
	var director := _director()
	director.loadObject({"raid_active": "yes", "raid_day": 4, "raids_cleared": 2})

	var err: String = _T.assert_false(
		director.raid_active, "an unreadable flag reads as 'no raid'")
	if err != "":
		_drop(director)
		return err

	# The real assertion: the fields AFTER the flag were still read, which is what proves
	# loadObject ran to the end rather than aborting on line one.
	var later: String = _T.assert_eq(
		director.raids_cleared, 2, "the reads after the flag still happened")
	_drop(director)
	return later


# --- the registry side --------------------------------------------------------


## Lightning is the charged skeleton's only source and the raid is the raider's, for the same
## reason: a type the ambient timer can trickle in is a type the player can simply wait for, and
## a raider wandering the island in daylight makes the nights mean nothing.
func test_raiders_are_never_trickled_in() -> String:
	for type in EnemyRegistry.RAIDER_TYPES:
		var err: String = _T.assert_false(
			EnemyRegistry.ambient_types().has(type),
			"'%s' is not an ambient type" % type)
		if err != "":
			return err
	return ""


func test_raiders_are_recognisable_by_type_alone() -> String:
	# This is what makes "how many raiders are left" survive a load: a reloaded raider comes back
	# through the ordinary enemy path with its type intact, and nothing has to be re-wired.
	for type in EnemyRegistry.RAIDER_TYPES:
		var known: String = _T.assert_true(
			EnemyRegistry.has_type(type), "'%s' is a registered type" % type)
		if known != "":
			return known

		var err: String = _T.assert_true(
			EnemyRegistry.is_raider(type), "'%s' reads as a raider" % type)
		if err != "":
			return err

	var ordinary: String = _T.assert_false(
		EnemyRegistry.is_raider(EnemyRegistry.BONE), "a plain skeleton is not a raider")
	if ordinary != "":
		return ordinary

	return _T.assert_false(
		EnemyRegistry.is_raider(EnemyRegistry.ELITE), "the boss is not a raider either")


## The wide hunt range is what turns a spawn into a raid, and it is authored into the scenes so
## a reloaded raider is still hunting. If it ever stops coming back from the scene, a raid
## becomes a group of enemies milling about where they landed — which reads as the raid never
## arriving rather than as a bug.
func test_a_raider_scene_carries_a_hunt_range_that_crosses_the_island() -> String:
	# A maxed island is radius 34 at 16px tiles, so the far coastline is ~544px from the centre
	# and a raider may be spawned on the opposite side of it from the player.
	const ISLAND_SPAN := 1100.0

	for type in EnemyRegistry.RAIDER_TYPES:
		var scene := EnemyRegistry.scene_for(type)
		var raider := scene.instantiate() as Enemy
		var range_value := raider.hunt_range
		raider.free()

		var err: String = _T.assert_gt(
			range_value, ISLAND_SPAN,
			"'%s' can see across a maxed island (hunt_range %.0f)" % [type, range_value])
		if err != "":
			return err

	return ""


func test_an_ambient_enemy_still_only_notices_you_up_close() -> String:
	# The other half of the same change: giving raiders a dial must not have moved the ordinary
	# island, where a wanderer noticing the player from across the map would be a different game.
	var bone := EnemyRegistry.scene_for(EnemyRegistry.BONE).instantiate() as Enemy
	var range_value := bone.hunt_range
	bone.free()

	return _T.assert_float_eq(
		range_value, 30.0, 0.001,
		"a plain skeleton still uses the 30px range EnemyIdle used to hardcode")
