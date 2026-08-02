extends RefCounted
class_name Juice

## Every "feel" number in the game, and the two APIs that spend them: screen shake and
## hit-stop.
##
## This exists for the same reason `Resources.TUNING` and `SkillTree` do — the numbers
## that decide how something *feels* are the ones most often retuned, and they are useless
## scattered across five files as bare literals. A reviewer asking "how hard does a boss
## death shake the screen, and how does that compare to a pickaxe swing?" should be able to
## answer it by reading one table. Everything below is either a constant with a rationale
## or a small static function that spends one.
##
## Nothing here is a Node and nothing here is an autoload:
##
##  * Adding an autoload means editing `project.godot`, and the shake/hit-stop state is a
##    handful of floats — a whole singleton Node for that is more machinery than the
##    problem has.
##  * `HealthManager` (systems/health_manager.gd) is the precedent: it extends RefCounted
##    and is held as a plain field precisely because the Node version leaked one object per
##    enemy. The same instinct applies to juice, which fires far more often than an enemy
##    spawns — so nothing in this file creates a node, and nothing it drives creates one
##    per event either. The particle emitters and the screen flash are all persistent
##    single instances that are reused and never freed.
##
## Static state lives in this class rather than on a node so a freed trigger (an enemy
## dying is the *most common* hit-stop trigger) cannot strand it. See `hit_stop` below.


# ---------------------------------------------------------------------------------------
# Screen shake
# ---------------------------------------------------------------------------------------
#
# The model is the genre-standard trauma one, and `world/camera.gd` implements it:
#
#   trauma      a value in 0..1 that events *add* to and time decays LINEARLY
#   shake       trauma ^ SHAKE_EXPONENT, so small traumas fall off much faster than big ones
#   offset      SHAKE_MAX_OFFSET * shake, sampled from coherent noise per axis
#
# The three properties that matter, and that the previous implementation had none of:
#
#  * Linear decay REACHES ZERO. The old code decayed with `lerpf(strength, 0, fade*delta)`,
#    which is geometric: it approaches zero asymptotically and never arrives. Its `_process`
#    guard was `if shake_strength > 0`, so it stayed true forever and the camera was still
#    being assigned a fresh random offset minutes later. The camera never returned to rest.
#  * Additive trauma with a clamp means two hits in one frame build to a bigger shake
#    instead of the second one overwriting the first, and nothing can drive the offset past
#    SHAKE_MAX_OFFSET no matter how many events land.
#  * Noise, not `randf_range` per axis. Independent uniform randoms every frame is a buzz —
#    high-frequency, uncorrelated, and at this camera's zoom it reads as the screen tearing
#    rather than as an impact. Coherent noise gives the camera a direction to move in for a
#    few frames at a time, which is what makes it read as a shake.

## World-space pixels of camera offset at trauma 1.0. Tiles are 16px and the camera is
## zoomed 8x, so 6 world px is ~48 screen px — a boss-death figure, which is why only
## Shake.MASSIVE ever reaches it.
const SHAKE_MAX_OFFSET := 6.0

## Squaring is what separates a pebble from a boss. It also means the shake table below has
## to be read as a *curve*, not a scale: trauma 0.5 is a quarter of full offset, not half.
const SHAKE_EXPONENT := 2.0

## Seconds for a full trauma of 1.0 to decay to exactly 0. Decay is linear, so any smaller
## trauma is a proportional fraction of this — a Shake.TINY gather swing (0.22) is over in
## 0.13s, which is what makes it a tick rather than a wobble.
const SHAKE_DURATION := 0.6

## Trauma lost per second. Derived, not tuned: it is the reciprocal of the duration above,
## and stating it that way is what guarantees trauma lands on exactly 0.0 rather than near it.
const SHAKE_TRAUMA_DECAY := 1.0 / SHAKE_DURATION

## Ceiling on accumulated trauma. Named rather than a literal 1.0 because SHAKE_EXPONENT is
## applied to it: any other value would silently change what "full shake" means.
const SHAKE_TRAUMA_MAX := 1.0

## Noise sampling. `frequency` scales the input, `speed` advances it, so the visible
## oscillation rate is roughly `frequency * speed` cycles per second — 0.5 * 40 = 20Hz,
## fast enough to read as an impact and slow enough to stay coherent across a few frames.
const SHAKE_NOISE_FREQUENCY := 0.5
const SHAKE_NOISE_SPEED := 40.0

## The two axes sample the same noise field at rows far enough apart to be uncorrelated —
## "far enough" being several wavelengths, and one wavelength here is 1/SHAKE_NOISE_FREQUENCY
## = 2 input units. Sampling both axes at the same row would move the camera along a
## diagonal only.
const SHAKE_NOISE_ROW_X := 0.0
const SHAKE_NOISE_ROW_Y := 137.0

## Named intensities. `apply_shake()` used to be called with `1` from an enemy hit, `1` from
## a resource breaking and nothing at all from the player taking damage — three events of
## wildly different weight asking for the same 1px jitter, which is the other half of why
## the old shake never landed. Anything that shakes the screen now names how much it matters
## and the table decides what that costs.
enum Shake {
	TINY,     ## One swing of a pickaxe. Fires several times per gather, so it must not accumulate into a rumble.
	LIGHT,    ## A hit landed on an enemy; a resource node giving way.
	MEDIUM,   ## A level-up; a scene-backed node breaking.
	HEAVY,    ## The player taking damage; an enemy dying.
	MASSIVE,  ## Reserved for the boss. Nothing in the ordinary loop should reach it.
}

const SHAKE_TRAUMA := {
	Shake.TINY: 0.22,
	Shake.LIGHT: 0.35,
	Shake.MEDIUM: 0.50,
	Shake.HEAVY: 0.70,
	Shake.MASSIVE: 1.00,
}


## Trauma an intensity is worth. Pure, so a test of the curve exercises the same table the
## game spends. An unknown intensity is LIGHT rather than an error: a missing entry should
## under-shake, not crash a hit.
static func trauma_for(intensity: Shake) -> float:
	return SHAKE_TRAUMA.get(intensity, SHAKE_TRAUMA[Shake.LIGHT])


## Offset multiplier for a given trauma. Pure and shared with the camera, so the curve is
## testable without a viewport.
static func shake_amount(trauma: float) -> float:
	return pow(clampf(trauma, 0.0, SHAKE_TRAUMA_MAX), SHAKE_EXPONENT)


## The one way anything in the game shakes the screen. `source` is used only to reach the
## scene tree; the camera is found by group and cached, so a caller needs no reference to it
## (`enemies/enemy.gd` kept one purely for `apply_shake` and every new caller would have had
## to grow the same field).
##
## Silently does nothing when there is no camera — this is feedback, and a missing camera in
## a unit test must not fail a gameplay call.
static func shake(source: Node, intensity: Shake) -> void:
	var camera := _find_camera(source)
	if camera == null:
		return
	camera.add_trauma(trauma_for(intensity))


## Cached because `shake` is called several times a second during a gather and a group scan
## per swing is pure waste. Untyped on purpose: typing this as `Camera` would make
## systems/juice.gd and world/camera.gd statically reference each other, and camera.gd reads
## the constants above.
static var _camera: Node = null


static func _find_camera(source: Node) -> Node:
	if _camera != null and is_instance_valid(_camera) and _camera.is_inside_tree():
		return _camera
	_camera = null

	if source == null or not source.is_inside_tree():
		return null
	var tree := source.get_tree()
	if tree == null:
		return null

	for node in tree.get_nodes_in_group("Camera"):
		# Duck-typed rather than `is Camera`, for the same reason the type above is Node.
		if node.has_method("add_trauma"):
			_camera = node
			return _camera
	return null


# ---------------------------------------------------------------------------------------
# Hit-stop
# ---------------------------------------------------------------------------------------
#
# A few frames of slowed time on a kill or a heavy hit. This is the single most dangerous
# thing in this file: `Engine.time_scale` is global, and a stuck one does not look like a
# juice bug — it looks like the game has frozen or gone into slow motion permanently, with
# no in-game way out. Everything below is shaped by "what happens if the next line never
# runs", so it is worth stating exactly what the design rules out:
#
#  * NO TIMER AND NO CALLBACK. The dip ends at a WALL-CLOCK deadline that `tick()` compares
#    against. There is nothing to fire late, nothing to fire twice and nothing to be killed
#    early. A SceneTreeTimer would have had to be created from the trigger's tree, and the
#    most common trigger is an enemy dying — i.e. a node being freed in the same frame.
#  * NO NODE IS INVOLVED AT ALL. `hit_stop` takes no `source`, holds no reference and
#    connects to nothing, so "the trigger node was freed mid-dip" is not a case that can
#    exist rather than a case that is handled.
#  * WALL CLOCK, NOT SCALED TIME. `Time.get_ticks_msec()` is unaffected by `time_scale`, so
#    the dip cannot stretch its own deadline by 1/HIT_STOP_SCALE.
#  * TWO INDEPENDENT TICKERS. `world/camera.gd` and `player/player.gd` both call `tick()`
#    from `_process`, so neither one being freed, disabled or paused can strand the clock.
#    `tick()` is an integer compare and a bool test when idle; calling it twice a frame
#    costs nothing.
#  * RE-ENTRANCY IS ADDITIVE, NOT NESTED. A second hit during a dip pushes the deadline out
#    (never in) and never re-captures a "previous" scale. There is exactly one value the
#    release ever writes, and it is 1.0.
#
# On the devtools verbs, which also drive `Engine.time_scale`:
#
#  * `set-game-speed` sets it and leaves it. Hit-stop REFUSES TO ENGAGE unless the scale is
#    already 1.0, so a session deliberately running at 0.2x or 4x is never fought over — the
#    juice simply switches itself off, which is the correct precedence.
#  * `step-time` pins the scale to 1.0 for its duration and restores it afterwards. A hit
#    landing inside that window sees 1.0, engages, and releases to 1.0 — the same value
#    step-time is holding — and step-time's own restore runs last regardless.

## What time slows *to*. Deliberately not 0.0: a hard freeze reads as the game stuttering,
## which is the opposite of the intended "that landed". 0.12 is slow enough to feel like the
## world lurched and fast enough that nothing appears broken.
const HIT_STOP_SCALE := 0.12

## Dip lengths in real seconds. These are short on purpose — hit-stop is felt, not watched,
## and anything past ~0.15s starts reading as lag on a machine that is merely busy.
const HIT_STOP_LIGHT := 0.05   ## The player taking a hit.
const HIT_STOP_HEAVY := 0.10   ## An enemy dying.

## Hard ceiling on any single request, so a mistuned call site cannot ask for a second of
## slow motion. The deadline can still be *extended* by repeated hits, but only ever by
## another HIT_STOP_MAX at a time.
const HIT_STOP_MAX := 0.25

## Master switch, a var rather than a const so it can be turned off from the debugger while
## looking at something else without recompiling the intent out of the call sites.
static var hit_stop_enabled := true

static var _hit_stop_active := false
static var _hit_stop_deadline_msec := 0


## Dips `Engine.time_scale` for `duration` real seconds. Returns whether the dip engaged, so
## a caller (or a test) can tell "juice fired" from "something else owns the clock".
##
## Safe to call from anywhere at any rate: repeated calls extend one dip rather than nesting.
static func hit_stop(duration: float) -> bool:
	if not hit_stop_enabled or duration <= 0.0:
		return false

	# Someone else owns the clock — a devtools `set-game-speed`, most likely. Do not fight
	# it, and in particular do not "restore" it to 1.0 when the dip ends.
	if not _hit_stop_active and not is_equal_approx(Engine.time_scale, 1.0):
		return false

	var deadline := Time.get_ticks_msec() + int(minf(duration, HIT_STOP_MAX) * 1000.0)
	# maxi, so a light hit landing during a heavy dip can never cut the heavy one short.
	_hit_stop_deadline_msec = maxi(_hit_stop_deadline_msec, deadline) if _hit_stop_active else deadline
	_hit_stop_active = true
	Engine.time_scale = HIT_STOP_SCALE
	return true


## Called every frame from more than one place; see the two-ticker note above. Does nothing
## and allocates nothing while no dip is running.
static func tick() -> void:
	if not _hit_stop_active:
		return
	_tick_at(Time.get_ticks_msec())


## The clock injected, so the deadline logic is testable without sleeping. Not called
## directly by the game.
static func _tick_at(now_msec: int) -> void:
	if not _hit_stop_active:
		return
	if now_msec < _hit_stop_deadline_msec:
		return
	release_hit_stop()


## Ends any dip immediately and puts the clock back to normal. Idempotent, and the only
## place that writes 1.0.
static func release_hit_stop() -> void:
	if not _hit_stop_active:
		return
	_hit_stop_active = false
	_hit_stop_deadline_msec = 0
	Engine.time_scale = 1.0


static func is_hit_stopped() -> bool:
	return _hit_stop_active


# ---------------------------------------------------------------------------------------
# The gather loop
# ---------------------------------------------------------------------------------------
#
# Holding the gather key runs a timer for the pickaxe's full gather time — 2.0s on the
# starting wood pickaxe — and until now the only thing that happened in that interval was
# the progress bar filling. Two seconds of nothing is where a young player's attention goes,
# so the hold is now broken into discrete SWINGS, each of which lands.
#
# What a swing can actually do depends on which of the two resource representations is being
# hit, and they are not equally served:
#
#  * A `GameSceneResource` node (`is_scene_tile`, e.g. StoneResourceTest) is a real Node2D
#    with an AnimatedSprite2D, so it gets the full treatment: a squash/recoil on its sprite
#    per swing and a grow-and-fade pop when it breaks.
#  * An ORDINARY LAYER-1 TILEMAP CELL IS NOT A NODE. There is no transform to tween, no
#    modulate to flash and no per-cell material — the cell is a rectangle of a tileset atlas
#    drawn by the TileMapLayer. Nothing can make *the tile itself* wobble short of authoring
#    a second animated atlas frame per resource, which is a tileset change, not a code one.
#    So a tile cell gets everything that lives *beside* it instead: a chip burst at the
#    cell's world position, a pulse on the gather bar, and the camera tick. That is a
#    deliberate and honest asymmetry, not an oversight.

## Target seconds between swings. A wood pickaxe (2.0s) gets ~5 swings, a fast tier fewer —
## the cadence is what stays constant, which is what makes a faster tool read as "fewer
## swings to break it" rather than "the same animation, sped up".
const GATHER_SWING_INTERVAL := 0.42

## Even the fastest conceivable tool swings at least twice, so a gather is never a single
## instantaneous event with no build-up.
const GATHER_MIN_SWINGS := 2

## How long a swing's squash on a scene node takes to settle, in seconds. Shorter than the
## swing interval so the node is visibly at rest between hits — an overlapping wobble reads
## as a vibration, and vibration reads as "broken", not "being mined".
const NODE_HIT_TIME := 0.22

## Peak squash of a struck node: wider and shorter, as if compressed by the blow. Applied to
## the sprite's scale, which is 1.0 on every resource scene.
const NODE_HIT_SQUASH := Vector2(0.30, 0.24)

## How far the sprite recoils horizontally at the peak of a swing, in world pixels. Small:
## tiles are 16px and the node must not appear to leave its cell.
const NODE_HIT_RECOIL := 1.6

## How long a scene node's break pop runs for, which is also how long ResourceManager2 waits
## before the resource is actually removed — `ResourceManager2.SCENE_BREAK_TIME` is defined
## as this value. It lives here rather than there so `items/game_scene_resource.gd` can read
## it without the two classes referencing each other, which GDScript resolves badly.
const NODE_BREAK_TIME := 0.3

## The break pop itself: the node grows and fades rather than merely vanishing, so it reads as
## having burst.
const NODE_BREAK_GROW := 0.45

## How long the gather bar's per-swing pulse takes to settle, and how much it swells. This is
## the main per-swing feedback for tilemap cells, which have no sprite of their own to react.
const GATHER_PULSE_TIME := 0.18
const GATHER_PULSE_SCALE := 0.35

## Chips thrown per swing, and on the final break. Two persistent emitters rather than one
## with a changing `amount`: writing `amount` reallocates the particle buffer, and doing that
## several times a second during a gather is exactly the per-frame allocation this project
## gates on.
##
## The burst was 12 at 0.5s and that was too much: the drops a node yields are thrown from
## the same cell the burst fires at, on the same frame, so a dozen particles living half a
## second sat directly on top of the item and the player could not see what they had just
## earned. The effect was competing with the thing it was meant to celebrate. 6 at 0.3s
## still reads as a break — the z_index fix in resource_manager2.gd is what actually
## uncovers the drop, and this is the half that stops the burst being a cloud.
const GATHER_CHIP_AMOUNT := 4
const GATHER_BURST_AMOUNT := 6

## Lifetime of a chip and of a break-burst particle, in seconds.
const GATHER_CHIP_LIFETIME := 0.35
const GATHER_BURST_LIFETIME := 0.3

## Where the gather emitters and the collect sparkle draw, relative to their parent.
##
## Below the drops, which sit at z_index 1 (items/pick_up.tscn). Both emitters were at 60,
## chosen to clear the tilemap without reaching the damage numbers at 100 — but that also
## put them above every pickup, which is why a break hid its own loot.
##
## 0 is above layer_0 (-1) and level with the object layer, and at equal z the later draw
## wins: a TileMapLayer draws before the TileMap's node children, so a chip still appears
## over the tile it came off. Particles behind the item, item on top. Do not raise this to
## fix a "particles are hidden" report without checking what it does to the drops.
const PARTICLE_Z_INDEX := 0


## How many swings a gather of `gather_seconds` is divided into. Pure, so the cadence is
## testable without a timer. Always at least GATHER_MIN_SWINGS.
static func swings_for(gather_seconds: float) -> int:
	if gather_seconds <= 0.0:
		return GATHER_MIN_SWINGS
	return maxi(GATHER_MIN_SWINGS, int(floor(gather_seconds / GATHER_SWING_INTERVAL)))


# ---------------------------------------------------------------------------------------
# Pickups
# ---------------------------------------------------------------------------------------
#
# The cheapest dopamine in the game: a drop is minted every time anything is gathered,
# crafted, killed or destroyed, so anything done here is felt constantly. The arc out and
# the magnet-in easing already existed (`items/pick_up.gd`); what was missing was a
# beginning and an end — the drop simply appeared at full size and simply vanished on
# contact.

## Horizontal spread of the initial pop, in units of linear velocity. Widened from ±15: a
## near-vertical launch made a handful of drops from one node look like one drop, because
## they all followed the same line.
const PICKUP_LAUNCH_X := 28.0
## Vertical launch range. Negative is up; unchanged, this arc already reads well.
const PICKUP_LAUNCH_Y_MIN := -70.0
const PICKUP_LAUNCH_Y_MAX := -60.0

## The spawn pop: the sprite scales up from this fraction of its final size with a BACK ease,
## so a drop appears to be *thrown out of* the node rather than to fade in next to it.
const PICKUP_POP_FROM := 0.25
const PICKUP_POP_TIME := 0.18

## The landing squash, applied when the drop meets its shadow. Brief and wide — this is the
## moment the drop stops moving, and without it the transition from arc to magnet is invisible.
const PICKUP_LAND_SQUASH := Vector2(1.35, 0.65)
const PICKUP_LAND_TIME := 0.16

## Sparkle particles emitted where a drop is absorbed. One shared emitter, restarted per
## collect (see items/pick_up_manager.gd) — a burst of three simultaneous collects lands in
## nearly the same place, so sharing costs nothing visually and a node per collect would cost
## the orphan budget.
##
## Trimmed from 6 at 0.3s alongside the break burst, and for the same reason: a collect
## fires several times a second while the vacuum works through a yield, so the sparkles
## overlap into a haze around the player exactly where the remaining drops still are.
const PICKUP_SPARKLE_AMOUNT := 4
const PICKUP_SPARKLE_LIFETIME := 0.22

## Overshoot coefficient of `ease_out_back`. 1.70158 is the classic Penner value; it puts the
## peak of the overshoot at ~1.1x the target, which is a pop rather than a bounce.
const BACK_OVERSHOOT := 1.70158


## Back-out easing: overshoots the target and settles. `t` is 0..1 and the result is 0..1
## (transiently above 1 near the end, which is the whole point).
##
## Pure and shared with the pickup pop, so the curve is testable without a running game —
## which matters more here than usual, because everything else the pop does is a tween and a
## tween asserts nothing headless.
static func ease_out_back(t: float) -> float:
	var x := clampf(t, 0.0, 1.0) - 1.0
	return 1.0 + (BACK_OVERSHOOT + 1.0) * x * x * x + BACK_OVERSHOOT * x * x


# ---------------------------------------------------------------------------------------
# Milestones and combat
# ---------------------------------------------------------------------------------------

## Screen flash on a level-up. Gold, brief and low-alpha: this is a full-screen wash over a
## game a child is looking directly at, so it announces rather than blinds.
const LEVEL_UP_FLASH_COLOR := Color(1.0, 0.9, 0.45)
const LEVEL_UP_FLASH_ALPHA := 0.32
const LEVEL_UP_FLASH_TIME := 0.45

## Delay between the "LEVEL n!" splash and the "+1 SKILL POINT" one, in seconds. They used to
## spawn on the same frame and were told apart only by SplashText's vertical stagger. A
## banked point is now a rare event — the curve retune put the sixth point at 100 XP rather
## than 39 — so the two halves of the announcement are worth reading one after the other.
const LEVEL_UP_POINT_DELAY := 0.35

## Screen flash when the player is hit. Red, and weaker than the level-up flash: this fires
## while the player is being chased and must not obscure what is chasing them.
const DAMAGE_FLASH_COLOR := Color(0.9, 0.1, 0.12)
const DAMAGE_FLASH_ALPHA := 0.22
const DAMAGE_FLASH_TIME := 0.3

## Knockback squash on a struck enemy: stretched along the blow. Peak values, tweened back to
## 1.0 over KNOCKBACK_SQUASH_TIME.
const KNOCKBACK_SQUASH := Vector2(1.3, 0.75)
const KNOCKBACK_SQUASH_TIME := 0.18

## The death pop. An enemy used to `queue_free()` with its sprite at full opacity, so a kill
## was a thing that stopped existing rather than a thing that was defeated. It now swells and
## fades over the 0.2s the corpse was already waiting through for its particles.
const DEATH_POP_SCALE := 1.5
const DEATH_POP_TIME := 0.2
