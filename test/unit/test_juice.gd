extends RefCounted

## Guards the two parts of the juice pass that can fail invisibly and expensively:
## the camera returning to rest, and Engine.time_scale being handed back.
##
## WHAT THESE TESTS DELIBERATELY DO NOT COVER. Almost everything the juice pass added is a
## tween, a particle burst or a procedural transform on a sprite — the pickup pop, the node
## squash, the death pop, the screen flash, the gather bar pulse. Headless pumps no frames
## and has no viewport, so a test of any of those would either assert nothing or assert that
## a tween object exists, which is not the same claim as "the drop pops". Those are for the
## runtime pass; the honest headless surface is the pure math and the two pieces of global
## state, and that is what is below.
##
## The two that DO belong here are the ones where a bug is silent rather than ugly:
##
##  * Shake decay. The previous implementation used `lerpf(strength, 0, fade * delta)`, which
##    approaches zero asymptotically and never arrives, guarded by `if shake_strength > 0`.
##    The camera was therefore assigned a fresh random offset every frame for the rest of the
##    session after the first hit. Nothing about that looks like a bug in a screenshot — it
##    looks like the game is slightly blurry. test_shake_decays_to_exactly_zero is the
##    regression, and "exactly" is the whole assertion.
##  * Hit-stop. A stuck Engine.time_scale is the worst outcome in this whole change: it is
##    global, it has no in-game way out, and the most common trigger for it is an enemy dying
##    — i.e. a node being freed on the same frame. Every escape route is tested below.

var _T

var camera: Camera


func setup() -> void:
	camera = Camera.new()


func teardown() -> void:
	if camera != null and is_instance_valid(camera):
		camera.free()
	camera = null
	# Never leave a dipped clock behind for the next test in the suite, whatever this one did.
	Juice.release_hit_stop()
	Engine.time_scale = 1.0


## Drives the camera's own _process for `seconds` at a fixed step. The node never enters a
## tree — _process is what these tests exercise, and it must work without one.
func _run(seconds: float, step: float = 1.0 / 60.0) -> void:
	var frames := int(ceil(seconds / step))
	for _i in frames:
		camera._process(step)


# --- Shake curve ---

func test_trauma_is_clamped_to_one() -> String:
	camera.add_trauma(5.0)

	# Uncapped trauma would be cubed/squared into an offset far past SHAKE_MAX_OFFSET, i.e. a
	# hit that throws the camera off the island.
	return _T.assert_float_eq(camera.trauma, Juice.SHAKE_TRAUMA_MAX, 0.0001, "trauma is capped at 1.0")


func test_trauma_is_additive() -> String:
	camera.add_trauma(0.2)
	camera.add_trauma(0.3)

	# Assignment rather than accumulation was the old behaviour: a boss death landing one
	# frame before a pebble broke was *erased* by the pebble.
	return _T.assert_float_eq(camera.trauma, 0.5, 0.0001, "two hits in a row build")


func test_shake_amount_is_the_square_of_trauma() -> String:
	# The curve is what makes a pebble and a boss distinguishable at all; a linear mapping
	# makes every intensity in the table feel like the middle one.
	var err: String = _T.assert_float_eq(Juice.shake_amount(0.5), 0.25, 0.0001, "half trauma is a quarter offset")
	if err != "":
		return err
	return _T.assert_float_eq(Juice.shake_amount(1.0), 1.0, 0.0001, "full trauma is full offset")


func test_shake_amount_clamps_its_input() -> String:
	# shake_amount is called with the camera's trauma, which is already clamped — but it is
	# also a public pure function, and pow() of an out-of-range input is silently enormous.
	return _T.assert_float_eq(Juice.shake_amount(4.0), 1.0, 0.0001, "an out-of-range trauma still yields 1.0")


func test_the_intensity_table_is_ordered() -> String:
	# The whole point of the named API is that a pebble and a boss death are distinguishable.
	# A table edit that puts two of them out of order silently collapses that distinction.
	var previous := 0.0
	for intensity in [Juice.Shake.TINY, Juice.Shake.LIGHT, Juice.Shake.MEDIUM, Juice.Shake.HEAVY, Juice.Shake.MASSIVE]:
		var trauma: float = Juice.trauma_for(intensity)
		var err: String = _T.assert_gt(trauma, previous, "intensity %d shakes harder than the one below it" % intensity)
		if err != "":
			return err
		previous = trauma
	return _T.assert_float_eq(previous, 1.0, 0.0001, "the top of the table is exactly full trauma")


# --- Decay: the regression this pass exists for ---

func test_shake_decays_to_exactly_zero() -> String:
	camera.add_trauma(1.0)

	# Slightly longer than SHAKE_DURATION, so the assertion is "it has arrived", not "it is
	# about to".
	_run(Juice.SHAKE_DURATION + 0.1)

	var err: String = _T.assert_eq(camera.trauma, 0.0, "trauma reaches exactly 0.0, not merely close to it")
	if err != "":
		return err
	# The offset is the thing the player sees. Geometric decay left this at a random sub-pixel
	# value forever, because no code path ever assigned Vector2.ZERO.
	return _T.assert_true(camera.offset == Vector2.ZERO, "the camera offset returns to exactly Vector2.ZERO")


func test_the_camera_stays_at_rest() -> String:
	camera.add_trauma(1.0)
	_run(Juice.SHAKE_DURATION + 0.1)

	# The old _process ran its body whenever shake_strength > 0, which geometric decay made
	# permanently true. Running a further second must now change nothing at all.
	_run(1.0)

	var err: String = _T.assert_eq(camera.trauma, 0.0, "trauma stays at zero")
	if err != "":
		return err
	return _T.assert_true(camera.offset == Vector2.ZERO, "the offset is not re-randomised once at rest")


func test_shake_is_still_running_part_way_through() -> String:
	camera.add_trauma(1.0)

	_run(Juice.SHAKE_DURATION * 0.5)

	# Guards the other direction: a decay rate that overshoots would make every shake a
	# single-frame flicker, and test_shake_decays_to_exactly_zero would still pass.
	return _T.assert_gt(camera.trauma, 0.0, "a full-trauma shake is still going at the halfway mark")


func test_a_tiny_shake_is_over_quickly() -> String:
	camera.add_trauma(Juice.trauma_for(Juice.Shake.TINY))

	# A gather swing fires roughly every GATHER_SWING_INTERVAL seconds, so its shake has to be
	# finished before the next one lands or a hold becomes one continuous rumble.
	_run(Juice.GATHER_SWING_INTERVAL)

	return _T.assert_eq(camera.trauma, 0.0, "a swing's shake is done before the next swing")


# --- Hit-stop ---

func test_hit_stop_dips_the_time_scale() -> String:
	var engaged: bool = Juice.hit_stop(Juice.HIT_STOP_HEAVY)

	var err: String = _T.assert_true(engaged, "the dip engaged")
	if err != "":
		return err
	return _T.assert_float_eq(Engine.time_scale, Juice.HIT_STOP_SCALE, 0.0001, "time is slowed, not stopped")


func test_hit_stop_restores_exactly_one() -> String:
	Juice.hit_stop(Juice.HIT_STOP_HEAVY)

	Juice._tick_at(Juice._hit_stop_deadline_msec + 1)

	var err: String = _T.assert_float_eq(Engine.time_scale, 1.0, 0.0001, "the clock is handed back at exactly 1.0")
	if err != "":
		return err
	return _T.assert_false(Juice.is_hit_stopped(), "and the dip is no longer considered active")


func test_hit_stop_holds_until_its_deadline() -> String:
	Juice.hit_stop(Juice.HIT_STOP_HEAVY)
	var deadline: int = Juice._hit_stop_deadline_msec

	Juice._tick_at(deadline - 1)

	# A tick that releases early is the mirror of a stuck one: the dip becomes a single-frame
	# stutter that reads as a dropped frame rather than as impact.
	return _T.assert_float_eq(Engine.time_scale, Juice.HIT_STOP_SCALE, 0.0001, "still dipped one millisecond before the deadline")


func test_a_second_hit_extends_rather_than_nests() -> String:
	Juice.hit_stop(Juice.HIT_STOP_LIGHT)
	var first_deadline: int = Juice._hit_stop_deadline_msec

	# The re-entrant case: a second, heavier hit landing while the first dip is still running.
	Juice.hit_stop(Juice.HIT_STOP_HEAVY)
	var second_deadline: int = Juice._hit_stop_deadline_msec

	var err: String = _T.assert_gt(second_deadline, first_deadline, "the heavier hit pushed the deadline out")
	if err != "":
		return err

	# Past the first deadline but not the second: nothing may release yet.
	Juice._tick_at(first_deadline + 1)
	err = _T.assert_float_eq(Engine.time_scale, Juice.HIT_STOP_SCALE, 0.0001, "the first hit's deadline does not end the second hit's dip")
	if err != "":
		return err

	Juice._tick_at(second_deadline + 1)
	return _T.assert_float_eq(Engine.time_scale, 1.0, 0.0001, "and the later deadline does")


func test_a_lighter_hit_cannot_cut_a_heavy_dip_short() -> String:
	Juice.hit_stop(Juice.HIT_STOP_HEAVY)
	var heavy_deadline: int = Juice._hit_stop_deadline_msec

	Juice.hit_stop(Juice.HIT_STOP_LIGHT)

	# maxi, not assignment. Without it a stray light hit during a kill's dip would truncate it.
	return _T.assert_eq(Juice._hit_stop_deadline_msec, heavy_deadline, "the deadline only ever moves outwards")


func test_hit_stop_survives_the_trigger_being_freed() -> String:
	# The case that shaped the design. An enemy dying is the most common hit-stop trigger and
	# it queue_free()s itself in the same call, so anything that held a reference to the
	# trigger — a SceneTreeTimer created from its tree, a Callable bound to it — would be the
	# thing responsible for putting the clock back, and it would be gone.
	var trigger := Node.new()
	Juice.hit_stop(Juice.HIT_STOP_HEAVY)
	var deadline: int = Juice._hit_stop_deadline_msec
	trigger.free()

	Juice._tick_at(deadline + 1)

	return _T.assert_float_eq(Engine.time_scale, 1.0, 0.0001, "the clock is restored with the trigger long gone")


func test_hit_stop_refuses_when_something_else_owns_the_clock() -> String:
	# The devtools `set-game-speed` verb sets Engine.time_scale and leaves it. Hit-stop must
	# neither fight it nor "restore" it to 1.0 when the dip ends, so it simply declines.
	Engine.time_scale = 0.25

	var engaged: bool = Juice.hit_stop(Juice.HIT_STOP_HEAVY)

	var err: String = _T.assert_false(engaged, "the dip declined to engage")
	if err != "":
		return err
	return _T.assert_float_eq(Engine.time_scale, 0.25, 0.0001, "and left the other owner's scale alone")


func test_releasing_an_idle_hit_stop_changes_nothing() -> String:
	# release_hit_stop() is called from teardown paths and could plausibly be called from a
	# future one at any time; it must not stamp 1.0 over a deliberate set-game-speed.
	Engine.time_scale = 3.0

	Juice.release_hit_stop()

	return _T.assert_float_eq(Engine.time_scale, 3.0, 0.0001, "an idle release does not touch the clock")


func test_a_request_cannot_ask_for_arbitrary_slow_motion() -> String:
	var before := Time.get_ticks_msec()

	Juice.hit_stop(60.0)

	# HIT_STOP_MAX is the ceiling. A mistuned call site asking for a minute of slow motion is
	# a bug that would be indistinguishable from a hang.
	var held: int = Juice._hit_stop_deadline_msec - before
	return _T.assert_true(
		held <= int(Juice.HIT_STOP_MAX * 1000.0) + 5,
		"a %.1fs request is clamped to HIT_STOP_MAX (held %dms)" % [60.0, held]
	)


func test_a_zero_length_hit_stop_does_nothing() -> String:
	var engaged: bool = Juice.hit_stop(0.0)

	var err: String = _T.assert_false(engaged, "a zero-length dip does not engage")
	if err != "":
		return err
	return _T.assert_float_eq(Engine.time_scale, 1.0, 0.0001, "and the clock is untouched")


func test_the_camera_tick_releases_the_dip() -> String:
	# The camera is one of the two per-frame tickers. This is the wiring test: a dip whose
	# deadline has passed must end from _process alone, with no timer and no callback.
	Juice.hit_stop(Juice.HIT_STOP_HEAVY)
	# The deadline is moved into the past rather than waited out. Waiting would make the test
	# depend on how long a handful of headless frames take in wall-clock terms, which is the
	# kind of assertion that passes on a quiet machine and fails in CI.
	Juice._hit_stop_deadline_msec = Time.get_ticks_msec() - 1

	camera._process(1.0 / 60.0)

	return _T.assert_float_eq(Engine.time_scale, 1.0, 0.0001, "camera._process put the clock back")


# --- Pure helpers ---

func test_swings_scale_with_gather_time() -> String:
	# The wood pickaxe, the thing a new player spends their first ten minutes holding.
	var wood: int = Juice.swings_for(2.0)

	var err: String = _T.assert_gte(wood, 4, "a 2.0s gather is broken into at least four swings")
	if err != "":
		return err
	# The floor is what stops a fast tool collapsing into one instantaneous event with no
	# build-up at all.
	return _T.assert_eq(Juice.swings_for(0.1), Juice.GATHER_MIN_SWINGS, "even the fastest tool swings twice")


func test_swings_never_returns_zero() -> String:
	# A zero would be divided by in ResourceManager2.start_removing_resource.
	return _T.assert_gte(Juice.swings_for(0.0), Juice.GATHER_MIN_SWINGS, "a degenerate gather time still yields swings")


func test_ease_out_back_starts_and_ends_where_it_should() -> String:
	var err: String = _T.assert_float_eq(Juice.ease_out_back(0.0), 0.0, 0.0001, "the pop starts at nothing")
	if err != "":
		return err
	return _T.assert_float_eq(Juice.ease_out_back(1.0), 1.0, 0.0001, "and settles exactly on the target")


func test_ease_out_back_actually_overshoots() -> String:
	# The overshoot is the entire reason this curve was chosen over a linear or quad ease: it
	# is what makes a drop read as thrown out of a node rather than faded in beside it. A
	# BACK_OVERSHOOT accidentally set to 0 would leave every assertion above still passing.
	var peak := 0.0
	for i in 101:
		peak = maxf(peak, Juice.ease_out_back(float(i) / 100.0))

	return _T.assert_gt(peak, 1.0, "the curve rises past its target before settling")


func test_ease_out_back_clamps_out_of_range_input() -> String:
	return _T.assert_float_eq(Juice.ease_out_back(2.0), 1.0, 0.0001, "an input past 1.0 does not keep growing")
