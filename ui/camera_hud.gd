extends Control
class_name CameraHud

## Sizes the diegetic HUD (Player/Camera2D/UI) to exactly the camera's visible world
## area, so its children can use ordinary anchors.
##
## A Control under a CanvasLayer gets the viewport rect for free. This one does not:
## it hangs off Camera2D in world space, so its own rect is whatever the scene says
## and nothing recomputes it when the window changes. Before this script the HUD
## children carried camera-local offsets hand-tuned to the 1152x648 window (the left
## edge was literally x = -115, one unit inside 1152 / 4.935 / 2), and every one of
## them drifted toward the middle of the screen the moment the window grew.
##
## With the rect kept in sync, anchoring is normal: 0 is the left/top screen edge, 1
## is the right/bottom one, 0.5 is the centre, at any window size and any camera zoom.
## Children that are only a positioning handle for a group (PlayerInfo, Crafting) are
## anchored to a corner and keep their own children's offsets untouched.

var _camera: Camera2D


func _ready() -> void:
	_camera = get_parent() as Camera2D
	get_viewport().size_changed.connect(_resize_to_view)
	_resize_to_view()


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
