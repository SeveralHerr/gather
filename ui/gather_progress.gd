extends Node2D
class_name GatherProgress

## A small progress bar drawn above the resource node currently being gathered.
##
## Holding the gather key runs a timer for the equipped pickaxe's full gather time -
## 2.0s on the starting wood pickaxe - and without this the only feedback was a static
## highlight tile, which made the starter tool read as broken rather than slow.
##
## Driven from the real hold_timer rather than a duplicated duration, so it stays
## correct as pickaxe tiers change how long a swing takes.

const WIDTH := 14.0
const HEIGHT := 2.0
const BORDER := 1.0

## Drawn above the node being gathered; tiles are 16px.
const Y_OFFSET := -13.0

const BACKING_COLOR := Color(0.07, 0.06, 0.09, 0.85)
const FILL_START_COLOR := Color(0.44, 0.78, 0.35)
const FILL_END_COLOR := Color(0.96, 0.88, 0.33)

var progress: float = 0.0

## 1 -> 0 decay of the per-swing pulse. The bar swelling on each blow is the *main* per-swing
## feedback for an ordinary tilemap cell, which has no sprite of its own to squash — see the
## two-representations note in ResourceManager2._swing.
##
## Driven from `_process` on the node's `scale` rather than by a Tween: it fires several
## times per gather, and a scale write is cheaper than creating and killing a Tween at that
## rate. `_process` is off unless a pulse is running.
var _pulse: float = 0.0


func _ready() -> void:
	# Positioned in world space, so it does not inherit the tilemap's transform.
	top_level = true
	# Above the tilemap and its y-sorted children.
	z_index = 100
	visible = false
	set_process(false)


func begin(world_position: Vector2) -> void:
	global_position = world_position + Vector2(0.0, Y_OFFSET)
	progress = 0.0
	visible = true
	queue_redraw()


## One swing landed. Restarts the swell from full rather than adding to it, so a run of
## blows reads as a run of distinct hits.
func pulse() -> void:
	_pulse = 1.0
	set_process(true)


func _process(delta: float) -> void:
	_pulse = maxf(_pulse - delta / Juice.GATHER_PULSE_TIME, 0.0)
	if _pulse <= 0.0:
		scale = Vector2.ONE
		set_process(false)
		return
	# Squared, so the bar snaps out and eases back rather than swelling gradually.
	scale = Vector2.ONE * (1.0 + Juice.GATHER_PULSE_SCALE * _pulse * _pulse)


func set_progress(value: float) -> void:
	var clamped := clampf(value, 0.0, 1.0)
	if is_equal_approx(clamped, progress):
		return
	progress = clamped
	queue_redraw()


func finish() -> void:
	visible = false
	progress = 0.0
	# The bar is hidden rather than freed, so a pulse left mid-swell would still be there
	# — at the wrong size — the next time it is shown.
	_pulse = 0.0
	scale = Vector2.ONE
	set_process(false)


func _draw() -> void:
	var backing := Rect2(
		-WIDTH * 0.5 - BORDER,
		-HEIGHT * 0.5 - BORDER,
		WIDTH + BORDER * 2.0,
		HEIGHT + BORDER * 2.0
	)
	draw_rect(backing, BACKING_COLOR)

	if progress <= 0.0:
		return

	var fill := Rect2(-WIDTH * 0.5, -HEIGHT * 0.5, WIDTH * progress, HEIGHT)
	draw_rect(fill, FILL_START_COLOR.lerp(FILL_END_COLOR, progress))
