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

# The camera runs at ~4.9x zoom, so world-space sizes are multiplied by ~5 on
# screen. font_size 16 * WORLD_SCALE 0.2 * 4.9 zoom ~= 16 screen pixels.
const FONT_SIZE := 16
const WORLD_SCALE := 0.2
const OUTLINE_SIZE := 6
const BOX := Vector2(48.0, 20.0)

const RISE := 16.0
const LIFETIME := 0.7
const POP_TIME := 0.12
const SPAWN_OFFSET := Vector2(0.0, -10.0)
const TEXT_COLOR := Color(1.0, 0.95, 0.55)
const OUTLINE_COLOR := Color(0.05, 0.03, 0.05, 1.0)

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
	number._configure(amount)
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
	host.add_child(container)
	return container


func _configure(amount: int) -> void:
	name = "DamageNumber"
	text = str(amount)
	horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	clip_text = false
	size = BOX
	pivot_offset = BOX * 0.5
	scale = Vector2.ONE * WORLD_SCALE

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
	tween.tween_property(self, "scale", Vector2.ONE * WORLD_SCALE, POP_TIME) \
		.from(Vector2.ONE * WORLD_SCALE * 1.7) \
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
