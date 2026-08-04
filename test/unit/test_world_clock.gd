extends RefCounted

## Covers the clock's pure helpers: where the phase boundaries fall, that time wraps and
## counts days as it does, and that the tint curve is continuous everywhere — including
## across the wrap at 1.0, which is the one seam a screenshot of any single moment cannot
## show you.
##
## Most of it is static, so none of that needs a SceneTree. The lightning scheduling tests
## at the bottom need an instance, but only because the countdown is instance state — they
## build a bare `WorldClock.new()` and drive `tick()` by hand without ever adding it to a
## tree, which is safe precisely because the clock is a model that touches no nodes.
##
## The remaining parts that genuinely need a tree (the save round-trip) are covered in
## test_save_fidelity.gd and at runtime.

var _T

## How close two tints have to be to count as the same colour. One 8-bit step is ~0.004;
## this is a little looser so the smoothstep's own sampling does not trip it.
const TINT_EPSILON := 0.02


func _tints_close(a: Color, b: Color) -> bool:
	return (
		absf(a.r - b.r) <= TINT_EPSILON
		and absf(a.g - b.g) <= TINT_EPSILON
		and absf(a.b - b.b) <= TINT_EPSILON
	)


# --- phases -------------------------------------------------------------------


func test_each_phase_covers_the_range_it_claims() -> String:
	var cases := [
		[0.0, WorldClock.Phase.DAWN, "midnight-plus-nothing is dawn"],
		[0.05, WorldClock.Phase.DAWN, "mid-dawn"],
		[0.30, WorldClock.Phase.DAY, "mid-morning"],
		[0.50, WorldClock.Phase.DAY, "noon"],
		[0.65, WorldClock.Phase.DUSK, "mid-dusk"],
		[0.85, WorldClock.Phase.NIGHT, "the middle of the night"],
		[0.999, WorldClock.Phase.NIGHT, "the last moment before dawn"],
	]

	for case in cases:
		var err: String = _T.assert_eq(WorldClock.phase_for(case[0]), case[1], case[2])
		if err != "":
			return err

	return ""


func test_a_boundary_belongs_to_the_phase_it_opens() -> String:
	# Otherwise a phase is one frame long at its own start, and phase_changed fires twice.
	var err: String = _T.assert_eq(
		WorldClock.phase_for(WorldClock.DAWN_END), WorldClock.Phase.DAY, "exactly DAWN_END is day"
	)
	if err != "":
		return err

	err = _T.assert_eq(WorldClock.phase_for(WorldClock.DAY_END), WorldClock.Phase.DUSK, "exactly DAY_END is dusk")
	if err != "":
		return err

	return _T.assert_eq(WorldClock.phase_for(WorldClock.DUSK_END), WorldClock.Phase.NIGHT, "exactly DUSK_END is night")


func test_phase_for_wraps_rather_than_clamping() -> String:
	# advance() always hands over a wrapped value, but set_time_of_day and devtools do not
	# have to, and a clamp here would make every t > 1 read as night forever.
	var err: String = _T.assert_eq(WorldClock.phase_for(1.5), WorldClock.phase_for(0.5), "1.5 is the same as 0.5")
	if err != "":
		return err

	return _T.assert_eq(WorldClock.phase_for(-0.5), WorldClock.phase_for(0.5), "-0.5 is the same as 0.5")


func test_only_night_counts_as_dark() -> String:
	# Dusk is when the player decides whether to head home. Folding it in here would mean
	# the decision and its consequence arrive in the same moment.
	var err: String = _T.assert_true(WorldClock.is_dark(WorldClock.Phase.NIGHT), "night is dark")
	if err != "":
		return err

	for phase in [WorldClock.Phase.DAWN, WorldClock.Phase.DAY, WorldClock.Phase.DUSK]:
		err = _T.assert_false(WorldClock.is_dark(phase), "%s is not dark" % WorldClock.phase_name(phase))
		if err != "":
			return err

	return ""


# --- advancing ----------------------------------------------------------------


func test_a_full_day_of_delta_advances_exactly_one_day() -> String:
	var result := WorldClock.advance(0.0, WorldClock.DAY_LENGTH_SECONDS, WorldClock.DAY_LENGTH_SECONDS)

	var err: String = _T.assert_eq(result["days_elapsed"], 1, "one day elapsed")
	if err != "":
		return err

	return _T.assert_float_eq(result["time_of_day"], 0.0, 0.0001, "and lands back where it started")


func test_advancing_past_midnight_counts_the_day() -> String:
	# The boundary is at 1.0, not at dawn's end, so a step from late night into early dawn
	# has to roll the counter even though both sides are dim.
	var result := WorldClock.advance(0.95, 0.10 * WorldClock.DAY_LENGTH_SECONDS, WorldClock.DAY_LENGTH_SECONDS)

	var err: String = _T.assert_eq(result["days_elapsed"], 1, "crossing 1.0 counts a day")
	if err != "":
		return err

	return _T.assert_float_eq(result["time_of_day"], 0.05, 0.0001, "and wraps into dawn")


func test_a_step_within_one_day_counts_no_days() -> String:
	var result := WorldClock.advance(0.2, 0.1 * WorldClock.DAY_LENGTH_SECONDS, WorldClock.DAY_LENGTH_SECONDS)
	return _T.assert_eq(result["days_elapsed"], 0, "a step inside a day rolls nothing")


func test_a_long_step_counts_every_day_it_crossed() -> String:
	# step-time --seconds, a load that fast-forwards, or a stalled frame. A wrapped float
	# alone cannot distinguish one day from three, which is the whole reason advance()
	# returns both halves.
	var result := WorldClock.advance(0.5, 3.0 * WorldClock.DAY_LENGTH_SECONDS, WorldClock.DAY_LENGTH_SECONDS)

	var err: String = _T.assert_eq(result["days_elapsed"], 3, "three days of delta rolls three days")
	if err != "":
		return err

	return _T.assert_float_eq(result["time_of_day"], 0.5, 0.0001, "and lands at the same time of day")


func test_a_zero_length_day_does_not_divide_by_zero() -> String:
	# Reachable only by misconfiguration, but the failure mode is an infinite day count
	# rather than an error, so it is worth pinning.
	var result := WorldClock.advance(0.4, 10.0, 0.0)

	var err: String = _T.assert_float_eq(result["time_of_day"], 0.4, 0.0001, "the clock does not move")
	if err != "":
		return err

	return _T.assert_eq(result["days_elapsed"], 0, "and no days are counted")


# --- the tint curve -----------------------------------------------------------


func test_noon_is_full_daylight() -> String:
	var tint := WorldClock.tint_for(0.5)
	return _T.assert_true(
		_tints_close(tint, WorldClock.DAY_TINT), "noon is DAY_TINT, got %s" % tint
	)


func test_the_middle_of_the_night_is_the_night_tint() -> String:
	var tint := WorldClock.tint_for(0.85)
	return _T.assert_true(
		_tints_close(tint, WorldClock.NIGHT_TINT), "deep night is NIGHT_TINT, got %s" % tint
	)


func test_night_never_goes_below_the_readability_floor() -> String:
	# The floor exists so a 16px item sprite on the ground stays identifiable. Rain
	# multiplies on top of the time of day, so the darkest reachable state is a stormy
	# midnight and that is what has to clear the bar — not NIGHT_TINT on its own.
	var darkest := WorldClock.tint_for(0.85, WorldClock.Weather.RAIN)
	var floor_value: float = minf(darkest.r, minf(darkest.g, darkest.b))

	# Nothing reachable is darker than that, so the one number below is the whole guarantee.
	for t in [0.0, 0.05, 0.2, 0.5, 0.65, 0.7, 0.85, 0.99]:
		for weather in [WorldClock.Weather.CLEAR, WorldClock.Weather.RAIN]:
			var tint := WorldClock.tint_for(t, weather)
			var lowest: float = minf(tint.r, minf(tint.g, tint.b))
			if lowest < floor_value - 0.0001:
				return _T.assert_true(
					false,
					"t=%s weather=%d reaches %s, darker than a stormy midnight (%s)" % [t, weather, tint, darkest]
				)

	return _T.assert_gte(
		floor_value, 0.25,
		"even a stormy midnight stays above the point where 16px art stops being readable"
	)


func test_the_tint_is_continuous_across_every_boundary() -> String:
	# A jump in the tint is a visible flicker, and the boundaries are exactly where a
	# reader is least likely to be looking when it happens. Sampling either side of each
	# one is the only way this shows up without watching a full ten-minute cycle.
	var step := 0.0005

	for boundary in [WorldClock.DAWN_END, WorldClock.DAY_END, WorldClock.DUSK_END]:
		var before := WorldClock.tint_for(boundary - step)
		var after := WorldClock.tint_for(boundary + step)
		if not _tints_close(before, after):
			return _T.assert_true(
				false, "tint jumps at %s: %s -> %s" % [boundary, before, after]
			)

	return ""


func test_the_tint_is_continuous_across_midnight() -> String:
	# The wrap is the seam the other test cannot reach: dawn interpolates *out of* the
	# night colour, so if the DAWN arm and the NIGHT arm ever disagree about what night
	# looks like, the screen flickers once per day at exactly 0.0.
	var before := WorldClock.tint_for(1.0 - 0.0005)
	var after := WorldClock.tint_for(0.0005)

	return _T.assert_true(
		_tints_close(before, after), "tint jumps at midnight: %s -> %s" % [before, after]
	)


func test_twilight_passes_through_a_warm_colour() -> String:
	# Not a straight lerp between night and day. A straight lerp goes through the
	# desaturated blue-grey halfway between them, which reads as a screen fading up rather
	# than as a sunrise — the bug this curve exists to avoid.
	var mid_dusk := WorldClock.tint_for((WorldClock.DAY_END + WorldClock.DUSK_END) * 0.5)
	var straight := WorldClock.DAY_TINT.lerp(WorldClock.NIGHT_TINT, 0.5)

	var err: String = _T.assert_gt(
		mid_dusk.r - mid_dusk.b, straight.r - straight.b,
		"mid-dusk is warmer than the straight line between day and night"
	)
	if err != "":
		return err

	var mid_dawn := WorldClock.tint_for(WorldClock.DAWN_END * 0.5)
	return _T.assert_gt(mid_dawn.r, mid_dawn.b, "mid-dawn is warm too — the sun rises the colour it sets")


func test_rain_darkens_and_cools_whatever_the_hour_is() -> String:
	# Rain is a multiplier over the time of day, not a colour of its own, so it composes
	# with every hour the same way: an overcast noon and an overcast midnight are both the
	# hour they already were, darker and cooler.
	#
	# "Cooler" is measured as the blue-to-red RATIO, not as a difference. Under a
	# multiplicative tint every absolute gap between channels shrinks simply because
	# everything got darker, so `wet.b - wet.r` moves toward zero at night and a
	# difference-based check would report a warm midnight. The ratio is invariant to that.
	for t in [0.05, 0.3, 0.5, 0.65, 0.85]:
		var clear := WorldClock.tint_for(t, WorldClock.Weather.CLEAR)
		var wet := WorldClock.tint_for(t, WorldClock.Weather.RAIN)

		var err: String = _T.assert_true(
			wet.r < clear.r and wet.g < clear.g and wet.b < clear.b, "rain darkens every channel at t=%s" % t
		)
		if err != "":
			return err

		err = _T.assert_gt(
			wet.b / maxf(wet.r, 0.0001), clear.b / maxf(clear.r, 0.0001),
			"rain leans the hour cooler at t=%s (clear %s, wet %s)" % [t, clear, wet]
		)
		if err != "":
			return err

	return ""


# --- names --------------------------------------------------------------------


func test_weather_names_round_trip() -> String:
	# devtools and the save file both go through these, so a mismatch between them is a
	# storm that saves as rain and loads as clear.
	for weather in [WorldClock.Weather.CLEAR, WorldClock.Weather.RAIN]:
		var err: String = _T.assert_eq(
			WorldClock.weather_from_name(WorldClock.weather_name(weather)), weather, "weather survives a name round-trip"
		)
		if err != "":
			return err

	return ""


func test_an_unknown_weather_name_reads_as_clear() -> String:
	# A save written by a build with more weather types than this one. Clear is the answer
	# that leaves the world playable; raising here would abort loadObject and, because that
	# is `-> void`, do it silently.
	return _T.assert_eq(
		WorldClock.weather_from_name("hurricane"), WorldClock.Weather.CLEAR, "an unknown storm reads as clear"
	)


func test_every_phase_has_a_name() -> String:
	for phase in [WorldClock.Phase.DAWN, WorldClock.Phase.DAY, WorldClock.Phase.DUSK, WorldClock.Phase.NIGHT]:
		var err: String = _T.assert_false(WorldClock.phase_name(phase) == "unknown", "phase %d has a name" % phase)
		if err != "":
			return err

	return ""


# --- thunder ------------------------------------------------------------------


func test_thunder_is_simultaneous_with_an_overhead_bolt() -> String:
	# Zero distance is the whole reason a strike "on top of you" reads differently from a
	# distant one: the crack lands on the same frame as the flash.
	return _T.assert_float_eq(
		WorldClock.thunder_delay(0.0), 0.0, 0.0001, "a bolt overhead cracks with the flash"
	)


func test_thunder_delay_grows_with_distance() -> String:
	# The delay is the only cue the player has for how far away a bolt was, so it has to be
	# monotone in `distance`. A farther bolt whose thunder arrives sooner does not read as
	# weather, it reads as broken audio.
	var previous := -1.0

	for distance in [0.0, 0.1, 0.25, 0.5, 0.75, 0.9, 1.0]:
		var delay := WorldClock.thunder_delay(distance)
		var err: String = _T.assert_gt(
			delay, previous, "delay at %s is %s, not longer than the step before it (%s)" % [distance, delay, previous]
		)
		if err != "":
			return err
		previous = delay

	return _T.assert_float_eq(
		WorldClock.thunder_delay(1.0), WorldClock.THUNDER_DELAY_MAX, 0.0001,
		"the far horizon is exactly THUNDER_DELAY_MAX"
	)


func test_thunder_delay_clamps_a_distance_outside_the_range() -> String:
	# `distance` arrives from a signal, so a save, a devtools verb or some future bolt aimed
	# at the player could hand over anything. An unclamped negative becomes a Timer started
	# with a negative wait — thunder that simply never plays, and no error to say why.
	var err: String = _T.assert_float_eq(
		WorldClock.thunder_delay(-3.0), 0.0, 0.0001, "a negative distance is treated as overhead"
	)
	if err != "":
		return err

	return _T.assert_float_eq(
		WorldClock.thunder_delay(9.0), WorldClock.THUNDER_DELAY_MAX, 0.0001,
		"and nothing is farther away than the horizon"
	)


# --- lightning scheduling ------------------------------------------------------
#
# These build a bare WorldClock and call tick() by hand. Nothing on this path touches the
# tree, so the node is never added to one — and `running` is irrelevant because _process is
# never what advances it here.


func test_a_storm_eventually_produces_a_bolt() -> String:
	var clock := WorldClock.new()
	var hits: Array = []
	clock.lightning_struck.connect(func(distance: float) -> void: hits.append(distance))

	clock.set_weather(WorldClock.Weather.RAIN, 10.0 * WorldClock.LIGHTNING_MAX_GAP)

	# A second at a time, for longer than the widest gap, so this asserts that the countdown
	# elapses rather than that one enormous step jumped over it.
	for _i in int(WorldClock.LIGHTNING_MAX_GAP) + 5:
		clock.tick(1.0)

	var result: String = _T.assert_gte(
		hits.size(), 1, "a storm outlasting LIGHTNING_MAX_GAP strikes at least once"
	)

	if result == "":
		result = _T.assert_gt(
			clock.lightning_time_left, 0.0, "and the countdown re-arms rather than sticking at zero"
		)

	if result == "":
		for distance in hits:
			result = _T.assert_true(
				distance >= 0.0 and distance <= 1.0,
				"every emitted distance is inside 0..1, got %s" % distance
			)
			if result != "":
				break

	clock.free()
	return result


func test_clear_skies_never_flash() -> String:
	var clock := WorldClock.new()
	var hits: Array = []
	clock.lightning_struck.connect(func(distance: float) -> void: hits.append(distance))

	# Deliberately kept inside one day. Crossing midnight calls _roll_weather, which can start
	# a genuine storm, and that storm would fail this test for the one reason it is not about.
	# time_of_day starts at DAWN_END (0.1), so 500 of a 600-second day stops short of the wrap.
	for _i in 500:
		clock.tick(1.0)

	var result: String = _T.assert_eq(
		clock.weather, WorldClock.Weather.CLEAR,
		"the sky stayed clear — if it did not, the day-boundary guard above has slipped and the rest of this test means nothing"
	)

	if result == "":
		result = _T.assert_eq(hits.size(), 0, "500 clear seconds produce no bolts")

	if result == "":
		result = _T.assert_eq(
			clock.lightning_time_left, 0.0, "and nothing is left armed under a clear sky"
		)

	clock.free()
	return result


func test_going_clear_disarms_the_countdown() -> String:
	var clock := WorldClock.new()
	clock.set_weather(WorldClock.Weather.RAIN, 120.0)

	var result: String = _T.assert_gte(
		clock.lightning_time_left, WorldClock.LIGHTNING_MIN_GAP, "starting rain arms the countdown"
	)

	if result == "":
		result = _T.assert_gte(
			WorldClock.LIGHTNING_MAX_GAP, clock.lightning_time_left, "and never beyond the widest gap"
		)

	if result == "":
		clock.set_weather(WorldClock.Weather.CLEAR, 0.0)
		# Exactly zero rather than merely small: a remainder left here would sit out the whole
		# dry spell and then fire on the first tick of the next storm.
		result = _T.assert_eq(
			clock.lightning_time_left, 0.0, "going clear disarms it to exactly 0.0"
		)

	clock.free()
	return result


func test_one_huge_tick_emits_at_most_one_bolt() -> String:
	var clock := WorldClock.new()
	var hits: Array = []
	clock.lightning_struck.connect(func(distance: float) -> void: hits.append(distance))

	# A hundred gaps' worth of delta in a single step: step-time, a load that fast-forwards,
	# or a frame stalled behind an import. Forty flashes in one frame is nonsense the player
	# cannot see, so the skipped bolts are eaten rather than banked into a burst.
	clock.set_weather(WorldClock.Weather.RAIN, 100000.0)
	clock.tick(100.0 * WorldClock.LIGHTNING_MAX_GAP)

	var result: String = _T.assert_eq(
		hits.size(), 1, "one tick is one bolt however long the tick was, got %d" % hits.size()
	)

	if result == "":
		result = _T.assert_gte(
			clock.lightning_time_left, WorldClock.LIGHTNING_MIN_GAP,
			"and it re-arms with a full fresh gap rather than with the overshoot"
		)

	if result == "":
		# Without this the count above would also pass if the storm had simply ended early,
		# which is a different bug wearing the same result.
		result = _T.assert_eq(
			clock.weather, WorldClock.Weather.RAIN, "the storm itself outlived the step"
		)

	clock.free()
	return result


# --- lightning across a load ---------------------------------------------------


func test_a_saved_countdown_survives_the_load_that_restarts_the_storm() -> String:
	# The ordering hazard inside loadObject: set_weather ARMS a fresh random countdown, so a
	# restore written before that call is silently overwritten by a random number. Nothing
	# raises, nothing is logged, and the player is handed back a storm they did not save.
	#
	# 3.25 is below LIGHTNING_MIN_GAP on purpose — it is a value the arming code cannot
	# produce, so this cannot pass by coincidence.
	var clock := WorldClock.new()
	clock.loadObject({
		"time_of_day": 0.4,
		"day": 3,
		"weather": "rain",
		"weather_time_left": 90.0,
		"lightning_time_left": 3.25,
	})

	var result: String = _T.assert_float_eq(
		clock.lightning_time_left, 3.25, 0.0001,
		"the saved countdown survives set_weather's re-arm, so it was restored after it"
	)

	clock.free()
	return result


func test_a_save_from_before_lightning_loads_into_an_armed_storm() -> String:
	# No key at all, which is every save this project has written so far. Defaulting the
	# missing value to 0.0 would fire a bolt on the very first tick after the load; keeping
	# the gap set_weather just armed is what such a save would have had.
	var clock := WorldClock.new()
	clock.loadObject({"time_of_day": 0.4, "day": 3, "weather": "rain", "weather_time_left": 90.0})

	var result: String = _T.assert_gte(
		clock.lightning_time_left, WorldClock.LIGHTNING_MIN_GAP,
		"an old rainy save comes back armed rather than about to strike"
	)

	clock.free()
	return result


func test_loading_a_clear_sky_leaves_nothing_armed() -> String:
	# A stale countdown under a clear sky is a bolt out of nowhere on the next tick — and the
	# save it came from would look perfectly correct in a diff.
	var clock := WorldClock.new()
	clock.loadObject({"time_of_day": 0.4, "day": 3, "weather": "clear", "lightning_time_left": 7.5})

	var result: String = _T.assert_eq(
		clock.lightning_time_left, 0.0, "a clear save arms nothing, whatever the file claims"
	)

	clock.free()
	return result


func test_a_daytime_storm_is_about_as_dark_as_night() -> String:
	# The requirement in words: a storm should feel like dusk arriving early, not like a grey
	# filter. Before this it was 0.72 against night's 0.42 — perceptibly overcast and nowhere
	# near dark, which is what "it should be darker when storming" was reporting.
	#
	# Asserted as a band rather than a value. A floor because the whole point is that it goes
	# properly dark; a ceiling because a DAYTIME storm darker than actual midnight would make
	# night itself meaningless and would put the 16px art under the readability limit at the
	# one hour the player has no lantern ramp to compensate.
	var storm := WorldClock.tint_for(0.35, WorldClock.Weather.RAIN)
	var night := WorldClock.tint_for(0.85, WorldClock.Weather.CLEAR)

	var err: String = _T.assert_true(
		storm.r <= night.r * 1.35,
		"a daytime storm is near night brightness (storm %.2f, night %.2f)" % [storm.r, night.r]
	)
	if err != "":
		return err
	return _T.assert_true(
		storm.r >= night.r,
		"but not darker than night itself (storm %.2f, night %.2f)" % [storm.r, night.r]
	)


func test_the_storm_floor_stops_rain_compounding_into_the_dark() -> String:
	# RAIN_TINT is a multiply, so without STORM_FLOOR a storm at midnight lands around 0.21 —
	# under the limit where the art stops being identifiable, at the exact moment the player is
	# fighting in the dark and reading their health bar. The floor is what bounds that, and it
	# has to bound it without ever making rain BRIGHTEN an hour.
	var stormy_midnight := WorldClock.tint_for(0.85, WorldClock.Weather.RAIN)
	var clear_midnight := WorldClock.tint_for(0.85, WorldClock.Weather.CLEAR)

	var err: String = _T.assert_true(
		stormy_midnight.r >= WorldClock.STORM_FLOOR.r - 0.0001,
		"the floor holds at midnight (got %.3f)" % stormy_midnight.r
	)
	if err != "":
		return err
	# Ordering, not just magnitude: a floor set above the night tint would silently invert the
	# relationship and make storms a way to SEE better after dark.
	return _T.assert_true(
		stormy_midnight.r <= clear_midnight.r,
		"and rain never brightens an hour (storm %.3f vs clear %.3f)" % [stormy_midnight.r, clear_midnight.r]
	)
