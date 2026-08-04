extends RefCounted

## Covers the shape of the lightning flash: that it starts and ends at exactly nothing, that
## it stays inside 0..1 the whole way, and that it is genuinely two strikes rather than one
## smooth fade.
##
## The second of those is the one worth having a test for. A flash is over in half a second,
## so no screenshot can tell a double strike from a single one — one frame of either looks
## identical, and the difference is entirely in the sequence. That is why the curve lives in
## a pure static: it is the only form in which the shape can be asserted at all.
##
## Everything here is static, so none of it needs a SceneTree. The parts that do — the
## signal connection, the fold into the three canvases — are runtime concerns and are checked
## against a running game.

var _T

## Samples per flash. Fine enough that the two-frame attack is resolved by several samples,
## which is what stops the peak-finding below landing on the ramp instead of the top.
const SWEEP_STEPS := 1000

## Anything below this is the tail or the trough, not a strike. Used to keep floating-point
## noise in the long decay from being counted as a third peak.
const PEAK_FLOOR := 0.02


## The whole envelope, sampled evenly from 0 to `duration` inclusive.
func _sweep(duration: float) -> Array:
	var samples := []
	for i in range(SWEEP_STEPS + 1):
		var elapsed := duration * float(i) / float(SWEEP_STEPS)
		samples.append(SkyLighting.flash_envelope(elapsed, duration))
	return samples


# --- the ends -----------------------------------------------------------------


func test_the_envelope_is_exactly_zero_at_both_ends() -> String:
	# Not "close to zero". The caller multiplies the sky by `1.0 + envelope * peak`, so a
	# residue at the end of a flash is a world that never quite returns to its night colour —
	# and one that gets a little further from it with every bolt of the storm.
	var duration := SkyLighting.FLASH_DURATION

	var err: String = _T.assert_eq(SkyLighting.flash_envelope(0.0, duration), 0.0, "dark at the moment of the strike")
	if err != "":
		return err

	err = _T.assert_eq(SkyLighting.flash_envelope(duration, duration), 0.0, "dark again at exactly the end")
	if err != "":
		return err

	return _T.assert_eq(SkyLighting.flash_envelope(duration * 4.0, duration), 0.0, "and stays dark past the end")


func test_a_flash_that_has_not_started_is_dark() -> String:
	# _flash_elapsed is only ever driven forward from zero, but apply() is public and a
	# devtools verb can call it at any time, so a negative elapsed must read as "no flash"
	# rather than as an extrapolated one.
	return _T.assert_eq(SkyLighting.flash_envelope(-1.0, SkyLighting.FLASH_DURATION), 0.0, "a flash before its own start is dark")


func test_a_zero_length_flash_does_not_divide_by_zero() -> String:
	# The division is by `duration`, and the result of getting this wrong is not an error —
	# it is INF or NAN multiplied into the CanvasModulate, the sea and the HUD reciprocal all
	# at once, which renders as a blank screen with nothing in the log.
	var err: String = _T.assert_eq(SkyLighting.flash_envelope(0.1, 0.0), 0.0, "a zero-length flash is no flash")
	if err != "":
		return err

	return _T.assert_eq(SkyLighting.flash_envelope(0.1, -0.5), 0.0, "and neither is a negative one")


# --- the range ----------------------------------------------------------------


func test_the_envelope_stays_within_zero_and_one() -> String:
	# The envelope is the *fraction* of the bolt's peak gain; FLASH_PEAK_NEAR is what sets how
	# bright that gain is. If this ever exceeded 1.0 the near-bolt cap would silently stop
	# being a cap, and a close strike would clip the sky to white.
	var samples := _sweep(SkyLighting.FLASH_DURATION)

	for i in samples.size():
		var value: float = samples[i]
		if value < 0.0:
			return _T.assert_true(false, "envelope goes negative at sample %d: %s" % [i, value])
		if value > 1.0 + 0.0001:
			return _T.assert_true(false, "envelope exceeds 1.0 at sample %d: %s" % [i, value])

	return ""


func test_the_envelope_actually_reaches_full_brightness() -> String:
	# A curve that peaks at 0.6 makes FLASH_PEAK_NEAR a lie: the brightest possible bolt
	# would land at 60% of the value that constant claims to set.
	var samples := _sweep(SkyLighting.FLASH_DURATION)
	var highest := 0.0
	for i in samples.size():
		var value: float = samples[i]
		highest = maxf(highest, value)

	return _T.assert_gte(highest, 0.99, "the leader stroke reaches full, got %s" % highest)


# --- the double strike --------------------------------------------------------


func test_the_envelope_strikes_twice() -> String:
	# The property this whole curve exists for. A single smooth rise and fall over the same
	# half second is the same brightness for the same length of time and reads as a screen
	# wipe or a damage flash — right on every scalar, wrong as an event.
	var samples := _sweep(SkyLighting.FLASH_DURATION)

	var first := 0
	for i in samples.size():
		if samples[i] > samples[first]:
			first = i

	# Walk downhill out of the first strike, then uphill into the second. Reading the shape as
	# a sequence rather than as three separate extrema is what keeps this from depending on
	# where exactly the sampling happens to land.
	var trough := first
	while trough + 1 < samples.size() and samples[trough + 1] <= samples[trough]:
		trough += 1

	var second := trough
	while second + 1 < samples.size() and samples[second + 1] >= samples[second]:
		second += 1

	var err: String = _T.assert_gt(second, trough, "there is a second rise after the first strike falls")
	if err != "":
		return err

	var peak_one: float = samples[first]
	var peak_two: float = samples[second]
	var dip: float = samples[trough]

	err = _T.assert_gt(peak_two, PEAK_FLOOR, "the second strike is bright enough to see, got %s" % peak_two)
	if err != "":
		return err

	err = _T.assert_gt(peak_one, peak_two, "the return stroke is the smaller of the two")
	if err != "":
		return err

	# The dip is the part the eye reads as two events. Half the second peak is a generous
	# bar — the curve as tuned drops to a couple of percent — but it is the bar below which
	# the two strikes have merged into one wide bump.
	return _T.assert_gt(
		peak_two * 0.5, dip,
		"the sky goes dark between the strikes: trough %s against second peak %s" % [dip, peak_two]
	)


func test_the_envelope_has_exactly_two_peaks() -> String:
	# The sequence test above finds two; this one asserts there are no others. A third bump
	# in the tail would read as a stutter rather than as a storm, and it is the shape a
	# well-meant "smooth the decay" edit is most likely to introduce.
	var samples := _sweep(SkyLighting.FLASH_DURATION)
	var peaks := 0

	for i in range(1, samples.size() - 1):
		var value: float = samples[i]
		if value > PEAK_FLOOR and value > samples[i - 1] and value > samples[i + 1]:
			peaks += 1

	return _T.assert_eq(peaks, 2, "a leader stroke and a return stroke, and nothing else")


# --- distance -----------------------------------------------------------------


func test_the_peak_spans_the_two_named_constants() -> String:
	var err: String = _T.assert_float_eq(
		SkyLighting.flash_peak_for(0.0), SkyLighting.FLASH_PEAK_NEAR, 0.0001, "an overhead bolt flashes at FLASH_PEAK_NEAR"
	)
	if err != "":
		return err

	return _T.assert_float_eq(
		SkyLighting.flash_peak_for(1.0), SkyLighting.FLASH_PEAK_FAR, 0.0001, "a horizon bolt flashes at FLASH_PEAK_FAR"
	)


func test_a_further_bolt_is_always_a_dimmer_one() -> String:
	# Monotonic, not merely bracketed. The distance the clock rolls is continuous, so a curve
	# that dipped and recovered anywhere in the middle would make two different distances
	# produce the same flash while a third, further one produced a brighter.
	var previous := SkyLighting.flash_peak_for(0.0)

	for i in range(1, 101):
		var distance := float(i) / 100.0
		var peak := SkyLighting.flash_peak_for(distance)
		var err: String = _T.assert_gt(previous, peak, "distance %s flashes dimmer than the step before it" % distance)
		if err != "":
			return err
		previous = peak

	return ""


func test_an_out_of_range_distance_clamps() -> String:
	# Nothing in the game rolls a distance outside 0..1 today, so this is a guard on the
	# interface rather than on a caller. Extrapolating would let a negative distance produce
	# a gain above FLASH_PEAK_NEAR, which is precisely the value chosen so the sky does not
	# clip to white.
	var err: String = _T.assert_float_eq(
		SkyLighting.flash_peak_for(-3.0), SkyLighting.FLASH_PEAK_NEAR, 0.0001, "closer than overhead is still overhead"
	)
	if err != "":
		return err

	return _T.assert_float_eq(
		SkyLighting.flash_peak_for(12.0), SkyLighting.FLASH_PEAK_FAR, 0.0001, "further than the horizon is still the horizon"
	)
