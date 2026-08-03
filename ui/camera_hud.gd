extends Control
class_name CameraHud

## Sizes the diegetic HUD (Player/Camera2D/HUD) to exactly the camera's visible world
## area, so its children can use ordinary anchors, and scales what it draws so the
## numbers stay legible as the window grows.
##
## A Control under a CanvasLayer gets the viewport rect for free. This one does not:
## it hangs off Camera2D in world space, so its own rect is whatever the scene says
## and nothing recomputes it when the window changes. Before this script the HUD
## children carried camera-local offsets hand-tuned to the 1152x648 window (the left
## edge was literally x = -115, one unit inside 1152 / 4.935 / 2 at the 4.935 zoom the
## camera ran at back then), and every one of them drifted toward the middle of the
## screen the moment the window grew.
##
## With the rect kept in sync, anchoring is normal: 0 is the left/top screen edge, 1
## is the right/bottom one, 0.5 is the centre, at any window size and any camera zoom.
## Children that are only a positioning handle for a group (PlayerInfo) are anchored
## to a corner and keep their own children's offsets untouched.
##
## ## Why anything here needs scaling at all
##
## The camera's zoom is fixed at 8 and the project's stretch mode is "disabled", so a
## HUD unit is always 8 screen pixels no matter how large the window is. Everything
## under here therefore has a *constant pixel size*: the HP bar is 26 HUD units wide,
## which is 208 screen pixels on a phone and 208 screen pixels on a 4K monitor. That is
## nearly half a portrait phone's width and a rounding error on a desktop, and the
## desktop end is the complaint — the bars and labels are far too small on the window
## size the game actually ships with (1920x1080).
##
## `_apply_legibility_scale()` multiplies the readable groups by UiTheme's viewport
## factor, floored at 1.0 so a small screen never ends up with *less* than the sizes
## these offsets were authored for. Positions are scaled with the group only where
## the group is measured from the top-left corner, so nothing here computes an
## on-screen position from a viewport dimension — that is the gather-6fx bug.

## The children whose contents are read at a glance and are sized by *transform*: the
## fps readout and the HP/XP group.
##
## `FloatingText` was the third entry. Both it and the node are gone: it was a second
## "+N xp" readout duplicating the world splash, and being transform-scaled it was the
## ugly one — glyphs reaching the screen at 0.45 (its own scale) * 8 (camera zoom) * 1.5
## (this factor), i.e. a rasterized atlas magnified 5.4x under the HUD's NEAREST filter.
##
## The lesson outlives the node. Scaling the *transform* of something made of glyphs
## resamples an atlas; scaling its `font_size` re-rasterizes. Anything added to this list
## that is text should size itself the second way (see `ui/splash_text.gd`, which pins its
## transform to 1/zoom for exactly this reason). This list is for bars and boxes.
const SCALED_CHILDREN := ["FpsLabel", "PlayerInfo"]

## Never shrink below what the scene authored. UiTheme.SCALE_MIN is 0.85, which on
## a phone would make an already-constant-pixel HUD smaller than it is today for no
## gain — the problem this fixes is at the large end.
const MIN_LEGIBILITY_SCALE := 1.0

var _camera: Camera2D

## The scene-authored scale and position of each entry in SCALED_CHILDREN, captured
## once. Every pass recomputes from these rather than from the current values, so a
## resize cannot compound — the mistake PlayerStats documents for stat deltas.
var _base_scale: Dictionary = {}
var _base_position: Dictionary = {}


func _ready() -> void:
	_camera = get_parent() as Camera2D
	if _camera == null:
		# The one way to misconfigure this script, and otherwise it fails silently:
		# the rect keeps whatever the scene authored and the HUD drifts exactly as it
		# did before the script existed.
		push_error("CameraHud: parent is not a Camera2D, so the HUD rect will not track the view")

	_capture_base_transforms()

	get_viewport().size_changed.connect(_resize_to_view)
	_resize_to_view()


## The zoom the rect was last computed against, so _process only re-derives when it moves.
##
## Camera2D has no zoom_changed signal, so tracking it means comparing. This file and
## CLAUDE.md both promise the HUD holds "at any window size and any camera zoom", but only
## size_changed was ever wired up — nothing writes zoom today, so it was contract drift
## rather than a live bug, and the first screen-shake, zoom-on-death or map view would have
## stranded the whole HUD off-screen (gather-xgi).
##
## A per-frame Vector2 comparison against a cached value is cheaper than the resize it
## guards, and this node already runs its own _process for the FPS readout.
var _last_zoom := Vector2.ZERO


func _process(_delta: float) -> void:
	if _camera == null:
		return

	if not _camera.zoom.is_equal_approx(_last_zoom):
		_resize_to_view()


func _capture_base_transforms() -> void:
	for child_name in SCALED_CHILDREN:
		var child := get_node_or_null(NodePath(child_name)) as Control
		if child == null:
			continue
		_base_scale[child_name] = child.scale
		_base_position[child_name] = child.position


func _resize_to_view() -> void:
	if _camera == null:
		return

	# Zoom is a divisor here: Camera2D zoom scales the canvas, not this node, so one
	# world unit covers `zoom` screen pixels. A zero would be a division by zero and
	# a degenerate rect, so leave the last good size in place instead.
	var zoom := _camera.zoom
	if is_zero_approx(zoom.x) or is_zero_approx(zoom.y):
		return

	var view := get_viewport_rect().size / zoom
	size = view
	position = -view * 0.5

	_apply_legibility_scale()


## The factor the HUD grows its readable groups by on this viewport. Public and static
## because a child that sizes itself in `font_size` rather than by transform (the xp
## readout) still has to arrive at the same on-screen size as the rest of the HUD, and
## two copies of `maxf(1.0, UiTheme.scale_for_node(...))` would be two chances to drift.
static func legibility_scale(node: Node) -> float:
	return maxf(MIN_LEGIBILITY_SCALE, UiTheme.scale_for_node(node))


func _apply_legibility_scale() -> void:
	var factor := legibility_scale(self)

	for child_name in SCALED_CHILDREN:
		var child := get_node_or_null(NodePath(child_name)) as Control
		if child == null:
			continue

		var base_scale: Vector2 = _base_scale.get(child_name, Vector2.ONE)
		child.scale = base_scale * factor

		# A Control scales about its own origin, so a group measured from the
		# top-left corner has to have its offset grow with it or the enlarged
		# groups above it overlap it — the fps line sits directly under the XP bar
		# and the two would collide. Anything anchored to the centre or to an edge
		# is already placed by its anchors and is left alone.
		if is_zero_approx(child.anchor_left) and is_zero_approx(child.anchor_top):
			var base_position: Vector2 = _base_position.get(child_name, Vector2.ZERO)
			child.position = base_position * factor
