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

enum Emphasis {
	NORMAL,  ## Ordinary event: xp from a gather, a craft, a pickup.
	BIG,     ## Milestone: a level-up or a banked skill point.
}

const CONTAINER_NAME := "SplashTexts"
const WORLD_HOST_PATH := "Main/Node2D"

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

## Rotating slot index so simultaneous splashes do not perfectly overlap. Static on
## purpose: the whole point is to spread splashes across *different* instances.
static var _stagger_index := 0

var _base_scale := WORLD_SCALE
var _lifetime := LIFETIME
var _rise := RISE
var _freed := false


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


## Convenience wrapper for the commonest case. Non-positive amounts spawn nothing:
## an event that granted no xp must not pop a "+0 XP".
static func spawn_xp(source: Node, world_position: Vector2, amount: int) -> SplashText:
	if amount <= 0:
		return null
	return spawn(source, world_position, format_xp(amount), color_for_xp(amount))


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
	modulate = Color(1.0, 1.0, 1.0, 1.0)

	var drift := randf_range(-DRIFT_X, DRIFT_X)
	var tween := create_tween()
	tween.set_parallel(true)
	tween.tween_property(self, "position:y", position.y - _rise, _lifetime) \
		.set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)
	tween.tween_property(self, "position:x", position.x + drift, _lifetime) \
		.set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_OUT)
	tween.tween_property(self, "scale", Vector2.ONE * _base_scale, POP_TIME) \
		.from(Vector2.ONE * _base_scale * POP_OVERSHOOT) \
		.set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
	tween.tween_property(self, "modulate:a", 0.0, _lifetime * FADE_FRACTION) \
		.set_delay(_lifetime * (1.0 - FADE_FRACTION))
	tween.chain().tween_callback(_finish)

	_arm_guard()


# Backstop: if the tween is killed before it completes this still removes the node.
func _arm_guard() -> void:
	var tree := get_tree()
	if tree == null:
		return
	# Scaled time (not ignore_time_scale) so the guard always trails the tween.
	var guard := tree.create_timer(_lifetime + 1.0, true, false, false)
	guard.timeout.connect(_on_guard_timeout)


func _on_guard_timeout() -> void:
	_finish()


func _finish() -> void:
	if _freed:
		return
	_freed = true
	queue_free()
