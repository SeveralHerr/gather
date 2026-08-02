extends Label
class_name SplashText

# General-purpose floating world-space splash: "+3 XP", "LEVEL 7!", "+1 SKILL POINT".
#
# Lifetime is owned by the splash, never by whatever triggered it. The label is
# parented to a persistent container in the world, so an enemy that dies from the same
# hit that spawned its splash can neither take the splash down with it nor leak it. A
# SceneTreeTimer guard frees the node even if the animation is somehow stranded.
#
# Two splashes fired in the same frame at the same spot would otherwise draw exactly on
# top of each other - a gather that pays xp and a pickup that pays xp are one frame
# apart - so every spawn takes the next slot in a small vertical stagger ring and adds
# a little horizontal jitter.
#
# XP is the exception, and spawn_xp handles it specially. XP does not arrive as discrete
# events: felling one tree pays 1 xp for the node and another 1 for every third item the
# pickup vacuum sweeps up, so a few seconds of gathering used to put a drifting column of
# "+1 XP" labels in the air. Those are one thing happening to the player, so they are now
# one label that swells, warms and hangs in place - see _absorb_xp.
#
# ---------------------------------------------------------------------------------------
# WHY THIS DOES NOT USE A TWEEN, AND WHY THE SCALE IS 1/ZOOM
# ---------------------------------------------------------------------------------------
#
# Two things went wrong with the tween-driven version and both are worth stating, because
# both are easy to reintroduce.
#
# 1. IT WAS BLURRY. A Label rasterizes its glyphs once at `font_size` and the GPU then
#    resamples that atlas through the accumulated transform. The transform here is
#    `scale * Camera2D.zoom`, and the scale constant was tuned when the camera was at
#    4.935 (0.2 * 4.935 = 0.987, near enough to 1:1). The zoom is 8 now, so the same 0.2
#    was magnifying a 16px atlas by 1.6x through the engine-default LINEAR filter. That is
#    the entire "the xp text looks soft" bug.
#
#    So: the transform scale is pinned to exactly `1.0 / zoom`, read from the live camera
#    rather than hardcoded, and every size change - emphasis, xp swell - is a change of
#    `font_size`, which re-rasterizes. Glyphs are therefore always drawn at 1:1 when the
#    splash is at rest, and `font_size` is literally the on-screen pixel height. The pop
#    is the one deliberate exception: it is a transform, it is fractional, and it lasts
#    POP_TIME - softness for 0.18s during a squash is motion, not blur.
#
#    Do not "simplify" a swell back into `scale`. It reads as a resampled bitmap, which is
#    what it is.
#
# 2. THE TWEEN WAS CHURNING. `_absorb_xp` fires several times a second during a gather and
#    each absorb killed and rebuilt a four-track parallel tween. This is the same
#    allocation-per-event shape that `HealthManager` and the shared particle emitters were
#    fixed for, and the house pattern for high-frequency reactions is a procedural
#    `_process` driver with a decaying float (see `ui/gather_progress.gd` and
#    `items/game_scene_resource.gd`). Absorbing is now four field writes and a reset of
#    `_age` - no allocation, no killed tween leaving a transform stranded, and the curves
#    below can be shaped freely instead of being whatever `Tween.TransitionType` offers.

enum Emphasis {
	NORMAL,  ## Ordinary event: xp from a gather, a craft, a pickup.
	BIG,     ## Milestone: a level-up or a banked skill point.
}

const CONTAINER_NAME := "SplashTexts"
const WORLD_HOST_PATH := "Main/World"

## The sparkle emitter parks here, NOT inside CONTAINER_NAME: `devtools_ext/commands.gd`
## reports `live_splashes` as the child count of the splash container and reads a permanent
## resident as a leak that never drains.
const SPARKLE_NAME := "SplashSparkle"
const HIT_PARTICLES := preload("res://world/vfx/hit_particles.tscn")

## Rasterized glyph height, and - because the transform below is exactly 1/zoom - the
## on-screen pixel height as well. Tiles are 16px at zoom 8, i.e. 128 screen px.
##
## This is now the ONLY "+N xp" on screen. There used to be a second one - a corner readout
## under the HUD - and the splash was sized to share the screen with it. With that gone the
## splash carries the whole readout and is sized to be read at a glance: 34px is about a
## quarter of a tile, and an xp streak swells it to 59.
const FONT_SIZE := 34
const BIG_FONT_SIZE := 56

## Fallback transform scale, used only when there is no camera to ask (a unit test, or the
## split second before one exists). It is 1/8 because `main.tscn`'s Camera2D is at zoom 8 -
## see `pixel_scale()`, which is what the game actually uses.
const WORLD_SCALE := 0.125

## Outline at the base font size. Scaled with the font in `_apply_font_size` so a swollen
## number keeps the same proportion of halo rather than growing a slab. Heavy enough that
## the text survives over a bright grass tile without a backing panel.
const OUTLINE_SIZE := 5

## Big enough for "+1 SKILL POINT" at BIG_FONT_SIZE, in screen pixels (the net scale is 1.0,
## so box units and screen pixels are the same thing here). The label is centred on its pivot
## and `mouse_filter` is IGNORE, so surplus box costs nothing but a clipped one is a bug -
## `clip_text` is off, but a Label still lays out inside its rect.
const BOX := Vector2(480.0, 88.0)

# --- Flight -----------------------------------------------------------------------------

## World pixels climbed over one life. World, not screen: 12 here is ~96 screen px at zoom 8.
const RISE := 12.0
const LIFETIME := 0.85
const FADE_FRACTION := 0.4
const SPAWN_OFFSET := Vector2(0.0, -10.0)

## Horizontal sway over the life, and the random spread of the launch point.
const DRIFT_X := 4.0
const JITTER_X := 3.0

const STAGGER_SLOTS := 4
const STAGGER_STEP := 4.0

# --- The pop ----------------------------------------------------------------------------

## Seconds for the impact squash to settle. Shorter than a swing so a run of gathers reads
## as a series of distinct hits on the number rather than one continuous wobble.
const POP_TIME := 0.18

## The shape of the impact: thin and tall, as if the number were punched upward. Because it
## settles through `Juice.ease_out_back` the axes cross their target and come back, so x
## overshoots wide while y undershoots flat - anti-correlated, which is what makes it read
## as squash-and-stretch instead of a zoom.
const POP_SQUASH := Vector2(0.5, 1.55)

## The same shape at a fraction of the energy, for an absorbed xp tick. A gather fires these
## several times a second and the full spawn squash repeated at that rate is a seizure.
const POP_SQUASH_ABSORB := Vector2(0.82, 1.18)

## Milestones get a fatter pop than an xp tick, from a wider start.
const POP_SQUASH_BIG := Vector2(0.35, 1.8)

# --- The impact flash -------------------------------------------------------------------

## For the first breath the glyphs are blown out to white and the outline to the splash's own
## colour, then both settle. This is the single cheapest thing on this list and the one that
## makes a number read as having *landed* rather than having appeared.
const FLASH_TIME := 0.11
const FLASH_COLOR := Color(1.0, 1.0, 1.0)

# --- Colours ----------------------------------------------------------------------------

const OUTLINE_COLOR := Color(0.05, 0.03, 0.05, 1.0)
const DEFAULT_COLOR := Color(1.0, 1.0, 1.0)
const COLOR_LEVEL := Color(1.0, 0.86, 0.25)
const COLOR_POINT := Color(0.78, 0.62, 1.0)

# XP colour ramp. A trickle of +1s stays a cool, quiet blue so the constant pickup and
# building ticks do not shout; a fat gather or a boss kill warms up to gold.
const COLOR_XP_SMALL := Color(0.62, 0.88, 1.0)
const COLOR_XP_MEDIUM := Color(0.55, 1.0, 0.62)
const COLOR_XP_LARGE := Color(1.0, 0.78, 0.28)
const XP_MEDIUM_AT := 3
const XP_LARGE_AT := 8

# --- XP coalescing ----------------------------------------------------------------------
#
# How far a new xp award may be from the live xp splash and still be folded into it, in
# world pixels. Four tiles: everything that pays xp while gathering (the node, the drops,
# a kill, a craft at the station being fed) happens within arm's reach of the player, and
# anything further away is a different event that deserves its own label.
const XP_STACK_RADIUS := 64.0

## Ceiling on how long one xp label may keep absorbing, in seconds. Without it a player who
## never stops gathering never sees the number resolve - it just keeps climbing, which reads
## as a broken counter rather than as a reward. At the cap the label finishes its rise and
## the next tick starts a fresh one.
const XP_STACK_MAX_LIFE := 2.5

## Each absorbed tick re-rasterizes the label a step larger, so a run of gathers builds one
## number that visibly swells. A multiplier on `font_size`, NOT on the transform - see the
## header. The cap is what stops a long streak from filling the screen.
const XP_STACK_SCALE_STEP := 0.1
const XP_STACK_SCALE_MAX := 1.75

## World pixels an absorbing label may drift above where it first appeared. Every absorb
## restarts the flight from wherever the label currently is, so without a ceiling a ten-tick
## streak walks the number off the top of the screen. Capped, it hangs over the player and
## pulses, which is the read we want: one fat number sitting there getting fatter.
const XP_MAX_CLIMB := 20.0

## Rotation wobble on a streak, in degrees at full amplitude and cycles per second. Amplitude
## grows with the streak and decays across each flight, so the first tick is straight and a
## six-tick run is visibly rattling.
const WOBBLE_MAX_DEG := 5.0
const WOBBLE_HZ := 6.5
const WOBBLE_PER_TICK := 1.1

## Sparkles thrown when the running xp total crosses a colour band, and when a milestone
## lands. One shared emitter, restarted per burst - the same reasoning as
## `PickUpManager.collect_sparkle`.
const SPARKLE_AMOUNT := 6
const SPARKLE_LIFETIME := 0.32

## Pitch of the tier-up blip, per band. A three-note rise, so a gather that warms all the way
## to gold is audibly a small tune rather than the same click three times.
const TIER_PITCH := [1.0, 1.26, 1.5]
const TIER_VOLUME_DB := -9.0

## Rotating slot index so simultaneous splashes do not perfectly overlap. Static on
## purpose: the whole point is to spread splashes across *different* instances.
static var _stagger_index := 0

## The xp splash currently in the air, if any. Static because the whole point is that the
## next xp award finds the previous one. Always reached through _live_xp_splash(), which is
## what makes a freed or expired label indistinguishable from none at all.
static var _live_xp: SplashText = null

## The shared sparkle emitter. Static and never freed, like every other emitter in the game.
static var _sparkle: GPUParticles2D = null

# --- Instance state ---------------------------------------------------------------------

## The settled transform scale, always exactly 1/zoom. Named `_base_scale` because it is the
## scale the pop settles back onto; it is deliberately NOT how the splash changes size.
var _base_scale := WORLD_SCALE
var _lifetime := LIFETIME
var _rise := RISE
var _freed := false

## Base font size before the xp swell: FONT_SIZE or BIG_FONT_SIZE.
var _font_base := FONT_SIZE
## Swell multiplier on `_font_base`, 1.0 .. XP_STACK_SCALE_MAX.
var _swell := 1.0

var _colour := DEFAULT_COLOR

## Flight. `_age` is seconds into the current flight and `_flight_origin` is where it began;
## an absorb resets the first and re-anchors the second to wherever the label already is.
var _age := 0.0
var _flight_origin := Vector2.ZERO
var _drift := 0.0
var _spawn_y := 0.0

## Decaying reaction timers. Both count *up* to their duration and then stop costing anything.
var _pop_age := 0.0
var _pop_squash := POP_SQUASH
var _flash_age := 0.0
var _flash_settled := false

## Running total shown by an xp splash, where it was first put, and how many ticks have been
## folded in. All unused by every other kind of splash.
var _xp_total := 0
var _xp_origin := Vector2.ZERO
var _xp_born_msec := 0
var _xp_streak := 0
var _xp_tier := 0

## Which armed guard is the live one. A splash that absorbs re-arms its backstop, and the
## timer already ticking must then not free a label that is still animating.
var _guard_generation := 0


## Spawns a splash at a world position. `source` is only used to reach the scene tree;
## the splash does not become its child, so `source` may be freed immediately after.
## Returns the splash, or null when there is no tree/world container to put it in.
static func spawn(
	source: Node,
	world_position: Vector2,
	text: String,
	colour: Color = DEFAULT_COLOR,
	emphasis: Emphasis = Emphasis.NORMAL
) -> SplashText:
	if source == null or not source.is_inside_tree() or text == "":
		return null

	var container := _get_container(source)
	if container == null:
		return null

	var splash := SplashText.new()
	splash._configure(text, colour, emphasis, pixel_scale(source))
	container.add_child(splash)
	splash._launch(world_position)

	if emphasis == Emphasis.BIG:
		# A milestone gets the burst on arrival; xp earns its sparkles by climbing a band.
		_sparkle_at(source, world_position)
	return splash


## The one xp splash. Non-positive amounts spawn nothing: an event that granted no xp must
## not pop a "+0 XP".
##
## Unlike every other splash this does not necessarily create a node. An award that lands
## near the label already in the air is added to it, so the player reads one number that
## climbs rather than a column of "+1 XP"s from the node, its drops and the pickup vacuum.
## The returned splash is therefore sometimes one an earlier call created.
static func spawn_xp(source: Node, world_position: Vector2, amount: int) -> SplashText:
	if amount <= 0:
		return null

	var live := _live_xp_splash()
	if live != null and live._xp_origin.distance_to(world_position) <= XP_STACK_RADIUS:
		live._absorb_xp(amount)
		return live

	var splash := spawn(source, world_position, format_xp(amount), color_for_xp(amount))
	if splash != null:
		splash._xp_total = amount
		splash._xp_origin = world_position
		splash._xp_born_msec = Time.get_ticks_msec()
		splash._xp_tier = tier_for_xp(amount)
		_live_xp = splash
	return splash


## The xp splash still eligible to absorb, or null. Freed, finished and over-age labels all
## answer null here, so there is one place that decides "is there one in the air" rather
## than three call sites each remembering a different two thirds of the question.
static func _live_xp_splash() -> SplashText:
	if _live_xp == null or not is_instance_valid(_live_xp) or _live_xp._freed or not _live_xp.is_inside_tree():
		_live_xp = null
		return null
	if Time.get_ticks_msec() - _live_xp._xp_born_msec > int(XP_STACK_MAX_LIFE * 1000.0):
		_live_xp = null
		return null
	return _live_xp


## "+3 XP". Pure, so the wording is testable without a scene tree.
static func format_xp(amount: int) -> String:
	if amount <= 0:
		return ""
	return "+%d XP" % amount


## Which colour band an xp amount falls in: 0 small, 1 medium, 2 large. Pure, and the single
## definition of the thresholds - `color_for_xp` reads it, and so does the tier-up celebration,
## so the sparkle can never fire on a step the colour did not actually take.
static func tier_for_xp(amount: int) -> int:
	if amount >= XP_LARGE_AT:
		return 2
	if amount >= XP_MEDIUM_AT:
		return 1
	return 0


## Where an xp amount sits on the colour ramp. Pure, and shared with spawn_xp so a test
## of the ramp exercises the colours the game actually shows.
static func color_for_xp(amount: int) -> Color:
	match tier_for_xp(amount):
		2:
			return COLOR_XP_LARGE
		1:
			return COLOR_XP_MEDIUM
		_:
			return COLOR_XP_SMALL


## The transform scale that draws one rasterized glyph pixel on exactly one screen pixel:
## the reciprocal of the camera zoom.
##
## Read from the live camera rather than hardcoded because this number has already gone
## stale once. `main.tscn` went from zoom 4.935 to zoom 8 in the scene restructure, the
## constant here did not, and the splash spent that time being magnified 1.6x through a
## linear filter. Asking the camera means the next zoom change is free.
static func pixel_scale(source: Node) -> float:
	if source == null or not source.is_inside_tree():
		return WORLD_SCALE
	var viewport := source.get_viewport()
	if viewport == null:
		return WORLD_SCALE
	var camera := viewport.get_camera_2d()
	if camera == null or camera.zoom.x <= 0.0:
		return WORLD_SCALE
	return 1.0 / camera.zoom.x


static func _get_container(source: Node) -> Node2D:
	var host := _world_host(source)
	if host == null:
		return null

	var existing := host.get_node_or_null(CONTAINER_NAME)
	if existing is Node2D:
		return existing as Node2D

	var container := Node2D.new()
	container.name = CONTAINER_NAME
	container.y_sort_enabled = false
	# Draw above the world; enemies sit at z_index 1, damage numbers at 100.
	container.z_index = 110
	# NEAREST, not the project-default LINEAR. At the settled 1:1 scale the two are
	# equivalent, but the pop is a fractional transform and linear filtering turns that
	# into the soft smear this whole rewrite exists to remove. Children inherit it through
	# TEXTURE_FILTER_PARENT_NODE, so this one line covers every splash.
	container.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	host.add_child(container)
	return container


static func _world_host(source: Node) -> Node:
	if source == null or not source.is_inside_tree():
		return null
	var tree := source.get_tree()
	if tree == null:
		return null
	var host: Node = tree.get_root().get_node_or_null(WORLD_HOST_PATH)
	if host == null:
		host = tree.current_scene
	return host


## A one-shot sparkle burst in world space, from a single shared emitter created on first
## use and never freed - a node per burst is exactly the orphan-budget leak that
## `HealthManager` and the gather emitters were fixed for.
static func _sparkle_at(source: Node, world_position: Vector2) -> void:
	var host := _world_host(source)
	if host == null:
		return

	if _sparkle == null or not is_instance_valid(_sparkle):
		_sparkle = HIT_PARTICLES.instantiate()
		_sparkle.name = SPARKLE_NAME
		_sparkle.top_level = true
		_sparkle.one_shot = true
		_sparkle.explosiveness = 1.0
		_sparkle.amount = SPARKLE_AMOUNT
		_sparkle.lifetime = SPARKLE_LIFETIME
		_sparkle.emitting = false
		# Above the drops rather than below them, unlike the gather and collect emitters:
		# this fires at head height where a splash is, not on the ground where the loot is,
		# so it cannot hide anything the player is trying to pick up.
		_sparkle.z_index = 2
		host.add_child(_sparkle)

	_sparkle.global_position = world_position
	# restart(), not `emitting = true`: a one-shot emitter that is still running ignores
	# the assignment, which would swallow every burst after the first.
	_sparkle.restart()


## A short blip when the running total crosses a colour band. Reached by path rather than
## through the `GameSoundManager` autoload identifier on purpose: the headless test runner
## is its own SceneTree and instantiates no autoloads, so naming the singleton directly
## would be an unresolved-identifier error inside a `-> String` test method - which the
## runner scores as a pass (see gather-1t9).
func _play_tier_blip(tier: int) -> void:
	var tree := get_tree()
	if tree == null:
		return
	var manager := tree.get_root().get_node_or_null("GameSoundManager")
	if manager == null or not manager.has_method("play_sound_pitched"):
		return
	var pitch: float = TIER_PITCH[clampi(tier, 0, TIER_PITCH.size() - 1)]
	manager.play_sound_pitched(SoundManager.SoundType.POP, pitch, TIER_VOLUME_DB)


func _configure(splash_text: String, colour: Color, emphasis: Emphasis, scale_factor: float) -> void:
	name = "SplashText"
	text = splash_text
	_colour = colour

	var big := emphasis == Emphasis.BIG
	_font_base = BIG_FONT_SIZE if big else FONT_SIZE
	_lifetime = LIFETIME * (1.6 if big else 1.0)
	_rise = RISE * (1.5 if big else 1.0)
	_pop_squash = POP_SQUASH_BIG if big else POP_SQUASH
	_base_scale = scale_factor

	horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	clip_text = false
	size = BOX
	pivot_offset = BOX * 0.5
	scale = Vector2.ONE * _base_scale

	_apply_font_size()
	# Settled colours, not the flash: a caller reads font_color on the spawn frame, and
	# _process writes the impact bloom from the first frame onward.
	_apply_colour(0.0)


## Writes the rasterized size and the outline that goes with it. Every size change in this
## class goes through here, which is what keeps the glyphs 1:1 - see the header.
func _apply_font_size() -> void:
	var px := maxi(1, int(round(_font_base * _swell)))
	add_theme_font_size_override("font_size", px)
	add_theme_constant_override(
		"outline_size", maxi(2, int(round(OUTLINE_SIZE * float(px) / float(FONT_SIZE))))
	)


## `flash` is 1.0 at the moment of impact and 0.0 at rest. At the peak the glyphs are white
## and the outline carries the splash's colour, so the label blooms and then resolves into
## itself.
func _apply_colour(flash: float) -> void:
	add_theme_color_override("font_color", _colour.lerp(FLASH_COLOR, flash))
	add_theme_color_override("font_outline_color", OUTLINE_COLOR.lerp(_colour, flash * 0.8))


func _launch(world_position: Vector2) -> void:
	var parent_2d := get_parent() as Node2D
	var local := world_position
	if parent_2d != null:
		local = parent_2d.to_local(world_position)

	var slot := _stagger_index % STAGGER_SLOTS
	_stagger_index += 1
	local += SPAWN_OFFSET
	local += Vector2(randf_range(-JITTER_X, JITTER_X), -STAGGER_STEP * slot)

	# pivot_offset is the visual centre, so subtract it to centre on the target.
	position = local - pivot_offset
	_spawn_y = position.y
	modulate = Color(1.0, 1.0, 1.0, 1.0)
	_begin_flight(_pop_squash)


## Starts (or restarts) the rise/sway/pop/fade from wherever the label currently is. An
## absorbed xp tick restarts it in place: the label keeps the height it has already climbed
## to and gets a fresh lifetime, rather than snapping back to the spawn point or fading out
## mid-gather.
## The pop and the flash are deliberately NOT written here, only armed. Their first values
## land on the first `_process` frame, which is what lets a caller read the settled `scale`
## and `font_color` on the spawn frame - the same contract the old `tween.from()` had, and
## the one `test_splash_spawn_configures_the_label` checks.
##
## The guard is re-armed on every flight: an absorbing label outlives the backstop its
## launch set, and a stale guard would free a number mid-streak.
func _begin_flight(squash: Vector2) -> void:
	_age = 0.0
	_flight_origin = position
	_drift = randf_range(-DRIFT_X, DRIFT_X)
	_pop_age = 0.0
	_pop_squash = squash
	_flash_age = 0.0
	_flash_settled = false
	set_process(true)
	_arm_guard()


func _process(delta: float) -> void:
	if _freed:
		return

	_age += delta
	var t := clampf(_age / _lifetime, 0.0, 1.0)

	# Flight. A cubic ease-out is a hard launch and a long hang - the number is thrown
	# upward and then floats, where a linear rise reads as drifting smoke.
	position = _flight_origin + Vector2(
		_drift * (1.0 - pow(1.0 - t, 2.0)),
		-_rise * (1.0 - pow(1.0 - t, 3.0))
	)

	# Pop. Squashed and stretched at impact, settling through an overshoot that carries the
	# axes past 1.0 in opposite directions.
	if _pop_age < POP_TIME:
		_pop_age += delta
		var p := Juice.ease_out_back(clampf(_pop_age / POP_TIME, 0.0, 1.0))
		scale = _pop_squash.lerp(Vector2.ONE, p) * _base_scale
	else:
		scale = Vector2.ONE * _base_scale

	# Impact flash, then settle once and stop paying for the theme write.
	if not _flash_settled:
		_flash_age += delta
		if _flash_age >= FLASH_TIME:
			_flash_settled = true
			_apply_colour(0.0)
		else:
			_apply_colour(1.0 - _flash_age / FLASH_TIME)

	# Streak wobble. Zero on a lone splash, so nothing rattles unless the player is on a run.
	if _xp_streak > 0:
		var amplitude := deg_to_rad(minf(_xp_streak * WOBBLE_PER_TICK, WOBBLE_MAX_DEG))
		rotation = sin(_age * TAU * WOBBLE_HZ) * amplitude * (1.0 - t)

	# Fade. Held at full opacity until the last FADE_FRACTION of the life, then squared so it
	# leaves decisively instead of lingering as a grey smudge.
	var fade_start := 1.0 - FADE_FRACTION
	if t <= fade_start:
		modulate.a = 1.0
	else:
		var f := (t - fade_start) / FADE_FRACTION
		modulate.a = (1.0 - f) * (1.0 - f)

	if t >= 1.0:
		_finish()


## Folds another xp award into this label: the number becomes the running total, the colour
## walks up the ramp with it, the label re-rasterizes a step larger, and the flight restarts
## so the whole thing re-pops. This is the "one juicy splash" - the reward for a good run of
## gathering is a single number getting fat, not a queue of small ones.
##
## Crossing a colour band is the moment worth celebrating, and it is the only one that gets
## sparkles, a blip and a camera tick: it happens at most twice per label, where an absorb
## happens several times a second.
func _absorb_xp(amount: int) -> void:
	_xp_total += amount
	_xp_streak += 1
	text = format_xp(_xp_total)
	_colour = color_for_xp(_xp_total)
	# Written through immediately, not left for _process to pick up when the flash settles.
	# The other two visible properties (text above, font_size below) land this frame, and a
	# colour that trails them by FLASH_TIME means an absorb that crosses a band renders the
	# *previous* band for a tenth of a second. _begin_flight re-arms the flash straight
	# after, so the bloom is unaffected - this only stops the theme lagging the field.
	_apply_colour(0.0)

	_swell = minf(_swell + XP_STACK_SCALE_STEP, XP_STACK_SCALE_MAX)
	_apply_font_size()

	# Cap the climb before restarting, so a long streak hangs and pulses over the player
	# instead of walking off the top of the screen one flight at a time.
	var climbed := _spawn_y - position.y
	_rise = clampf(XP_MAX_CLIMB - climbed, 1.0, RISE)
	_begin_flight(POP_SQUASH_ABSORB)

	var tier := tier_for_xp(_xp_total)
	if tier > _xp_tier:
		_xp_tier = tier
		_celebrate_tier(tier)


func _celebrate_tier(tier: int) -> void:
	var parent_2d := get_parent() as Node2D
	if parent_2d != null:
		_sparkle_at(self, parent_2d.to_global(position + pivot_offset))
	# TINY, the pickaxe-swing tick. Anything heavier collides with the level-up MEDIUM, and
	# this can fire twice inside one gather.
	Juice.shake(self, Juice.Shake.TINY)
	_play_tier_blip(tier)


# Backstop: if the animation is somehow stranded (scene change, a stopped process tree) this
# still removes the node.
func _arm_guard() -> void:
	var tree := get_tree()
	if tree == null:
		return
	_guard_generation += 1
	var generation := _guard_generation
	# Scaled time (not ignore_time_scale) so the guard always trails the flight.
	var guard := tree.create_timer(_lifetime + 1.0, true, false, false)
	guard.timeout.connect(func(): _on_guard_timeout(generation))


## `generation` says which armed guard fired; a stale one (the splash absorbed and re-armed
## since) must do nothing. The default -1 means "no generation, free it now" and is what a
## caller asking for the splash to go right now passes.
func _on_guard_timeout(generation: int = -1) -> void:
	if generation >= 0 and generation != _guard_generation:
		return
	_finish()


func _finish() -> void:
	if _freed:
		return
	_freed = true
	set_process(false)
	if _live_xp == self:
		_live_xp = null
	queue_free()
