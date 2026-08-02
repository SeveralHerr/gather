extends Label
class_name SplashText

# General-purpose floating world-space splash: "+3 XP", "LEVEL 7!", "+1 SKILL POINT".
#
# Modelled on DamageNumber (ui/damage_number.gd) and deliberately built the same way:
# entirely in code, so it depends on no font/art/scene asset, using the engine default
# Label font with a fat black outline so it stays legible over the 16px tile art.
#
# Lifetime is owned by the splash, never by whatever triggered it. The label is
# parented to a persistent container in the world, so an enemy that dies from the same
# hit that spawned its splash can neither take the splash down with it nor leak it. The
# tween ends in queue_free(), and a SceneTreeTimer guard frees the node even if the
# tween is killed early (scene change, tween cleanup, time-scale weirdness).
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
# one label - see _absorb_xp.

enum Emphasis {
	NORMAL,  ## Ordinary event: xp from a gather, a craft, a pickup.
	BIG,     ## Milestone: a level-up or a banked skill point.
}

const CONTAINER_NAME := "SplashTexts"
const WORLD_HOST_PATH := "Main/World"

# The camera runs at ~4.9x zoom, so world-space sizes are multiplied by ~5 on screen.
# font_size 16 * WORLD_SCALE 0.2 * 4.9 zoom ~= 16 screen pixels.
const FONT_SIZE := 16
const WORLD_SCALE := 0.2
const OUTLINE_SIZE := 6
# Wide enough for "+1 SKILL POINT" at the BIG scale; the label is centred on its pivot,
# so extra width costs nothing visually.
const BOX := Vector2(120.0, 22.0)

const RISE := 18.0
const LIFETIME := 0.85
const POP_TIME := 0.14
const POP_OVERSHOOT := 1.8
const FADE_FRACTION := 0.45
const SPAWN_OFFSET := Vector2(0.0, -10.0)
const OUTLINE_COLOR := Color(0.05, 0.03, 0.05, 1.0)

# The emphasis variant is a straight multiplier set rather than a second scene, so a
# level-up reads as "the same thing, but it matters more".
const BIG_SCALE_MULT := 1.9
const BIG_LIFETIME_MULT := 1.6
const BIG_RISE_MULT := 1.5

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

const STAGGER_SLOTS := 4
const STAGGER_STEP := 5.0
const JITTER_X := 4.0
const DRIFT_X := 6.0

# --- XP coalescing ---
#
# How far a new xp award may be from the live xp splash and still be folded into it, in
# world pixels. Four tiles: everything that pays xp while gathering (the node, the drops,
# a kill, a craft at the station being fed) happens within arm's reach of the player, and
# anything further away is a different event that deserves its own label.
const XP_STACK_RADIUS := 64.0

# Ceiling on how long one xp label may keep absorbing, in seconds. Without it a player who
# never stops gathering never sees the number resolve - it just keeps climbing, which reads
# as a broken counter rather than as a reward. At the cap the label finishes its rise and
# the next tick starts a fresh one.
const XP_STACK_MAX_LIFE := 2.5

# Each absorbed tick makes the label a little bigger and re-pops it, so a run of gathers
# builds one number that visibly swells instead of a queue of identical ones.
const XP_STACK_SCALE_STEP := 0.07
const XP_STACK_SCALE_MAX := 1.55
const XP_STACK_POP_OVERSHOOT := 1.35

## Rotating slot index so simultaneous splashes do not perfectly overlap. Static on
## purpose: the whole point is to spread splashes across *different* instances.
static var _stagger_index := 0

## The xp splash currently in the air, if any. Static because the whole point is that the
## next xp award finds the previous one. Always reached through _live_xp_splash(), which is
## what makes a freed or expired label indistinguishable from none at all.
static var _live_xp: SplashText = null

var _base_scale := WORLD_SCALE
var _lifetime := LIFETIME
var _rise := RISE
var _freed := false

## Running total shown by an xp splash, and where it was first put. Both are unused by
## every other kind of splash.
var _xp_total := 0
var _xp_origin := Vector2.ZERO
var _xp_born_msec := 0

## The tween driving the current rise/fade, kept so an absorbed tick can restart it.
var _tween: Tween

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
	splash._configure(text, colour, emphasis)
	container.add_child(splash)
	splash._launch(world_position)
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
		_live_xp = splash
	return splash


## The xp splash still eligible to absorb, or null. Freed, finished and over-age labels all
## answer null here, so there is one place that decides "is there one in the air" rather
## than three call sites each remembering a different two thirds of the question.
static func _live_xp_splash() -> SplashText:
	# is_inside_tree as well as validity: _absorb_xp restarts a tween, and create_tween()
	# on a detached node is an error rather than a no-op.
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


## Where an xp amount sits on the colour ramp. Pure, and shared with spawn_xp so a test
## of the ramp exercises the colours the game actually shows.
static func color_for_xp(amount: int) -> Color:
	if amount >= XP_LARGE_AT:
		return COLOR_XP_LARGE
	if amount >= XP_MEDIUM_AT:
		return COLOR_XP_MEDIUM
	return COLOR_XP_SMALL


static func _get_container(source: Node) -> Node2D:
	var tree := source.get_tree()
	if tree == null:
		return null

	var host: Node = tree.get_root().get_node_or_null(WORLD_HOST_PATH)
	if host == null:
		host = tree.current_scene
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
	host.add_child(container)
	return container


func _configure(splash_text: String, colour: Color, emphasis: Emphasis) -> void:
	name = "SplashText"
	text = splash_text

	var big := emphasis == Emphasis.BIG
	_base_scale = WORLD_SCALE * (BIG_SCALE_MULT if big else 1.0)
	_lifetime = LIFETIME * (BIG_LIFETIME_MULT if big else 1.0)
	_rise = RISE * (BIG_RISE_MULT if big else 1.0)

	horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	clip_text = false
	size = BOX
	pivot_offset = BOX * 0.5
	scale = Vector2.ONE * _base_scale

	add_theme_font_size_override("font_size", FONT_SIZE)
	add_theme_color_override("font_color", colour)
	add_theme_color_override("font_outline_color", OUTLINE_COLOR)
	add_theme_constant_override("outline_size", OUTLINE_SIZE)


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
	_animate(POP_OVERSHOOT)


## Runs the rise/drift/pop/fade from wherever the label currently is. Split out of _launch
## so an absorbed xp tick can restart the whole thing in place: the label keeps the height
## it has already climbed to and gets a fresh lifetime, rather than snapping back to the
## spawn point or fading out mid-gather.
func _animate(pop_overshoot: float) -> void:
	if _tween != null and _tween.is_valid():
		_tween.kill()

	modulate = Color(1.0, 1.0, 1.0, 1.0)

	var drift := randf_range(-DRIFT_X, DRIFT_X)
	_tween = create_tween()
	_tween.set_parallel(true)
	_tween.tween_property(self, "position:y", position.y - _rise, _lifetime) \
		.set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)
	_tween.tween_property(self, "position:x", position.x + drift, _lifetime) \
		.set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_OUT)
	_tween.tween_property(self, "scale", Vector2.ONE * _base_scale, POP_TIME) \
		.from(Vector2.ONE * _base_scale * pop_overshoot) \
		.set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
	_tween.tween_property(self, "modulate:a", 0.0, _lifetime * FADE_FRACTION) \
		.set_delay(_lifetime * (1.0 - FADE_FRACTION))
	_tween.chain().tween_callback(_finish)

	_arm_guard()


## Folds another xp award into this label: the number becomes the running total, the colour
## walks up the ramp with it, the label grows a step, and the animation restarts so the
## whole thing re-pops. This is the "one juicy splash" - the reward for a good run of
## gathering is a single number getting fat, not a queue of small ones.
func _absorb_xp(amount: int) -> void:
	_xp_total += amount
	text = format_xp(_xp_total)
	add_theme_color_override("font_color", color_for_xp(_xp_total))

	_base_scale = min(_base_scale + WORLD_SCALE * XP_STACK_SCALE_STEP, WORLD_SCALE * XP_STACK_SCALE_MAX)
	# A gentler overshoot than the initial pop: this fires several times a second during a
	# gather, and the spawn overshoot repeated at that rate reads as a wobble.
	_animate(XP_STACK_POP_OVERSHOOT)


# Backstop: if the tween is killed before it completes this still removes the node.
func _arm_guard() -> void:
	var tree := get_tree()
	if tree == null:
		return
	_guard_generation += 1
	var generation := _guard_generation
	# Scaled time (not ignore_time_scale) so the guard always trails the tween.
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
	if _live_xp == self:
		_live_xp = null
	queue_free()
