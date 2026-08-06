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

## The outline, and the floor of the empty track inside it.
##
## This bar is drawn straight onto the tilemap with nothing behind it, so the ink *is* the
## separation - there is no panel, no backdrop and no dim to do the job for it. The 0.85
## alpha it used to carry let bright grass show through the one element on screen that
## exists to be read at a glance; opaque is not a style preference here. See the COLOR_INK
## note in `ui/ui_theme.gd`.
##
## The track is the same recessed colour a list background takes in a panel, for the same
## reason: with only ink behind it, a part-filled bar and a short bar look identical.
const BACKING_COLOR := UiTheme.COLOR_INK
const TRACK_COLOR := UiTheme.COLOR_INSET

## The fill, and the fraction at which it flips from the first to the second.
##
## These two used to be lerped continuously across `progress`, which this palette does not
## do - a gradient is a soft edge by definition, and every other edge in the game is hard.
## It also answered the only question the colour is here to answer ("is this swing nearly
## done?") with a ramp of muddy in-between olives that nobody reads as a percentage; the
## *length* of the bar is the continuous readout and it is already there. One hard flip at
## FILL_SNAP_AT makes the colour a discrete event instead: green while the swing runs, gold
## once the payout is imminent. The names are kept because they still say which end of the
## gather each belongs to.
##
## Green over green grass survives only because of the ink around it. If the outline above
## is ever thinned or re-alpha'd, this is the thing that stops being legible first.
const FILL_START_COLOR := UiTheme.COLOR_GOOD
const FILL_END_COLOR := UiTheme.COLOR_GOLD
const FILL_SNAP_AT := 0.75

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

	# The well inside the outline. Drawn unconditionally, including at zero, so the ink stays
	# a border around something rather than becoming a solid blob whose width means nothing.
	draw_rect(Rect2(-WIDTH * 0.5, -HEIGHT * 0.5, WIDTH, HEIGHT), TRACK_COLOR)

	if progress <= 0.0:
		return

	var fill := Rect2(-WIDTH * 0.5, -HEIGHT * 0.5, WIDTH * progress, HEIGHT)
	draw_rect(fill, FILL_END_COLOR if progress >= FILL_SNAP_AT else FILL_START_COLOR)
