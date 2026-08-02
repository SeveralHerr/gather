extends Camera2D
class_name Camera

## Trauma-based screen shake. Every tunable lives in `systems/juice.gd`; this file is the
## mechanism only.
##
## What was here before was broken rather than merely crude, and it is worth recording what
## the failure actually was because none of it is visible from a screenshot:
##
##   func _process(delta):
##       if shake_strength > 0:
##           shake_strength = lerpf(shake_strength, 0, shakeFade * delta)
##           offset = randomOffset()
##
##  1. `lerpf(x, 0, k)` is geometric decay. It halves and halves and never reaches zero, so
##     `shake_strength > 0` stays true for the rest of the session. The camera was therefore
##     assigned a fresh random `offset` on EVERY FRAME FOREVER after the first hit — a
##     permanent sub-pixel jitter that nothing ever cleared, because no line in the file ever
##     assigned `offset = Vector2.ZERO`. The camera never returned to rest.
##  2. `randf_range` per axis, resampled every frame, is uncorrelated white noise. That is a
##     buzz, not a shake: at this camera's 8x zoom it reads as the screen tearing.
##  3. No cap and no curve. `apply_shake(s)` assigned `s` directly as a pixel amplitude, so
##     a second call *overwrote* the first (a big hit could be erased by a small one landing
##     the next frame) and there was no relationship between "how much this event matters"
##     and how much the screen moved.
##  4. The two exported knobs, `randomStrength` and `shakeFade`, were half dead:
##     `randomStrength` was never read at all, and every call site passed either nothing or
##     `1`, i.e. a one-pixel amplitude, for events as far apart as a pebble and a boss.
##
## The replacement is the standard trauma model — see the long comment in juice.gd for what
## each of its three properties buys.

## 0..1. Events add to it (`add_trauma`), time subtracts from it linearly.
var trauma: float = 0.0

## Advances the noise sample. Accumulated from delta rather than read off Time so the shake
## is deterministic under `step-time` and reproducible in a test.
var _noise_time: float = 0.0

## One FastNoiseLite for the life of the camera. Built as a field initializer so a camera
## constructed in a headless test (never entering the tree, so never running `_ready`) still
## has one — `_process` is what tests drive, and it must not allocate.
var _noise := FastNoiseLite.new()

## True while `offset` is already exactly Vector2.ZERO, so the resting camera does not
## rewrite the same value every frame.
var _at_rest := true


func _init() -> void:
	_noise.frequency = Juice.SHAKE_NOISE_FREQUENCY
	# A fixed seed would make every session shake identically from the same trauma; the
	# randomness that matters is *which* stretch of the field a shake samples.
	_noise.seed = randi()


func _ready() -> void:
	add_to_group("Camera")


## The named-intensity entry point, and the one gameplay should use — normally via
## `Juice.shake(self, Juice.Shake.HEAVY)`, which finds this node so callers need no
## reference to it.
func shake(intensity: Juice.Shake) -> void:
	add_trauma(Juice.trauma_for(intensity))


## Additive and clamped. Additive so two hits in the same frame build instead of the second
## erasing the first; clamped so no volume of events can drive the offset past
## Juice.SHAKE_MAX_OFFSET.
func add_trauma(amount: float) -> void:
	if amount <= 0.0:
		return
	trauma = clampf(trauma + amount, 0.0, Juice.SHAKE_TRAUMA_MAX)
	_at_rest = false


## Current offset multiplier, 0..1. Split out so a test can assert the curve without a
## viewport.
func shake_amount() -> float:
	return Juice.shake_amount(trauma)


func _process(delta: float) -> void:
	# One of the two independent hit-stop tickers. See the hit-stop section of juice.gd for
	# why there are two and why neither is a timer; when no dip is running this is a bool
	# test. It is deliberately outside the `_at_rest` early-out below — a hit-stop can
	# perfectly well be running while the camera is still.
	Juice.tick()

	if _at_rest:
		return

	# Linear, and floored at exactly 0.0. This is the line the old implementation did not
	# have: geometric decay left the camera jittering for the rest of the session.
	trauma = maxf(trauma - Juice.SHAKE_TRAUMA_DECAY * delta, 0.0)

	if trauma <= 0.0:
		offset = Vector2.ZERO
		_noise_time = 0.0
		_at_rest = true
		return

	_noise_time += delta
	var sample_at := _noise_time * Juice.SHAKE_NOISE_SPEED
	var amount := Juice.SHAKE_MAX_OFFSET * Juice.shake_amount(trauma)

	# Two rows of the same noise field, far enough apart to be uncorrelated. Coherent along
	# the sample axis, which is what gives the camera a direction to travel in for a few
	# frames rather than a new random point every frame.
	offset = Vector2(
		_noise.get_noise_2d(Juice.SHAKE_NOISE_ROW_X, sample_at),
		_noise.get_noise_2d(Juice.SHAKE_NOISE_ROW_Y, sample_at)
	) * amount

	# Deliberately no rotation, which the trauma model usually also drives: the diegetic HUD
	# is a child of this camera (Player/Camera2D/HUD), so rotating the camera would tilt the
	# health bar with it.
