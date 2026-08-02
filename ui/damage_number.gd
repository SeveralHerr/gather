extends Label
class_name DamageNumber

# Self-contained floating damage number.
#
# Built entirely in code so it depends on no art/font/scene assets: it uses the
# engine default Label font with a black outline, which stays legible over the
# 16px tile art.
#
# Lifetime is owned by the number itself, never by the thing that was hit. The
# label is parented to a persistent "DamageNumbers" container in the world, so
# an enemy that dies mid-animation cannot take the number down with it (and
# cannot leak it either). The tween ends in queue_free(), and a SceneTreeTimer
# guard frees the node even if the tween is somehow killed early.

const CONTAINER_NAME := "DamageNumbers"
const WORLD_HOST_PATH := "Main/World"

# The transform scale is pinned to exactly 1/zoom, read from the live camera, so the
# glyphs rasterize 1:1 on screen and `font_size` *is* the on-screen pixel height. See
# `SplashText.pixel_scale` for why this is not a hardcoded constant any more - the
# number here went stale once already when the camera moved from 4.935 to 8, which is
# the entire "the damage numbers look soft" bug.

## Rasterized glyph height, and - because the net scale is 1.0 - the on-screen pixel
## height too. Tiles are 16px at zoom 8, i.e. 128 screen px, so this has to be well
## clear of 16 to read at all. It sits under SplashText's 22 on purpose: a hit number
## fires far more often than an xp splash and must not out-shout it.
const FONT_SIZE := 18

## Fallback transform scale, used only when there is no camera to ask (a unit test, or
## the split second before one exists). 1/8 because `main.tscn`'s Camera2D is at zoom 8.
const WORLD_SCALE := 0.125

const OUTLINE_SIZE := 6

## Screen pixels, since the net scale is 1.0. Wide enough for four digits at FONT_SIZE
## plus the outline on both sides; the label is centred on its pivot and `mouse_filter`
## is IGNORE, so surplus box costs nothing.
const BOX := Vector2(96.0, 36.0)

const RISE := 16.0
const LIFETIME := 0.7
const POP_TIME := 0.12
const SPAWN_OFFSET := Vector2(0.0, -10.0)
const TEXT_COLOR := Color(1.0, 0.95, 0.55)
const OUTLINE_COLOR := Color(0.05, 0.03, 0.05, 1.0)

## The settled transform scale, always exactly 1/zoom. The pop overshoot below settles
## back onto this; it is deliberately not how the number changes size.
var _base_scale := WORLD_SCALE

var _freed_by_guard := false


# Spawns a damage number at a world position. `source` is only used to reach the
# scene tree; the number does not become its child, so `source` may be freed
# immediately afterwards.
static func spawn(source: Node, world_position: Vector2, amount: int) -> DamageNumber:
	if source == null or not source.is_inside_tree():
		return null
	var container := _get_container(source)
	if container == null:
		return null

	var number := DamageNumber.new()
	number._configure(amount, SplashText.pixel_scale(source))
	container.add_child(number)
	number._launch(world_position)
	return number


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
	# Draw above the world; enemies sit at z_index 1.
	container.z_index = 100
	# NEAREST, not the project-default LINEAR. At the settled 1:1 scale the two are
	# equivalent, but the pop is a fractional transform and linear filtering turns that
	# into a soft smear. Children inherit it through TEXTURE_FILTER_PARENT_NODE, so this
	# one line covers every number.
	container.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	host.add_child(container)
	return container


func _configure(amount: int, scale_factor: float = WORLD_SCALE) -> void:
	name = "DamageNumber"
	text = str(amount)
	_base_scale = scale_factor
	horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	clip_text = false
	size = BOX
	pivot_offset = BOX * 0.5
	scale = Vector2.ONE * _base_scale

	add_theme_font_size_override("font_size", FONT_SIZE)
	add_theme_color_override("font_color", TEXT_COLOR)
	add_theme_color_override("font_outline_color", OUTLINE_COLOR)
	add_theme_constant_override("outline_size", OUTLINE_SIZE)


func _launch(world_position: Vector2) -> void:
	var parent_2d := get_parent() as Node2D
	var local := world_position
	if parent_2d != null:
		local = parent_2d.to_local(world_position)
	local += SPAWN_OFFSET + Vector2(randf_range(-3.0, 3.0), 0.0)

	# pivot_offset is the visual centre, so subtract it to centre on the target.
	position = local - pivot_offset
	modulate = Color(1.0, 1.0, 1.0, 1.0)

	var drift := randf_range(-5.0, 5.0)
	var tween := create_tween()
	tween.set_parallel(true)
	tween.tween_property(self, "position:y", position.y - RISE, LIFETIME) \
		.set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)
	tween.tween_property(self, "position:x", position.x + drift, LIFETIME) \
		.set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_OUT)
	# A transform tween, deliberately: the 1.7 overshoot is fractional and therefore soft,
	# but softness for POP_TIME during an impact is motion, not blur. It settles onto
	# _base_scale, where the glyphs are 1:1 again.
	tween.tween_property(self, "scale", Vector2.ONE * _base_scale, POP_TIME) \
		.from(Vector2.ONE * _base_scale * 1.7) \
		.set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
	tween.tween_property(self, "modulate:a", 0.0, LIFETIME * 0.45) \
		.set_delay(LIFETIME * 0.55)
	tween.chain().tween_callback(_finish)

	_arm_guard()


# Backstop: if the tween is killed before it completes (scene change, tween
# cleanup, time-scale weirdness) this still removes the node from the tree.
func _arm_guard() -> void:
	var tree := get_tree()
	if tree == null:
		return
	# Scaled time (not ignore_time_scale) so the guard always trails the tween.
	var guard := tree.create_timer(LIFETIME + 1.0, true, false, false)
	guard.timeout.connect(_on_guard_timeout)


func _on_guard_timeout() -> void:
	if not _freed_by_guard:
		_freed_by_guard = true
		queue_free()


func _finish() -> void:
	_freed_by_guard = true
	queue_free()
