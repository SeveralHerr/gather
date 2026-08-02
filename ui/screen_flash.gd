extends ColorRect
class_name ScreenFlash

## A full-screen colour wash: gold on a level-up, red when the player is hit.
##
## Deliberately parameterised and colour-agnostic — every colour, alpha and duration lives in
## `systems/juice.gd` with the rest of the feel tuning, and callers pass them in. This file
## owns *where the rect lives and how long it lives for*, nothing else.
##
## Screen space, so it goes in the `UI` CanvasLayer and NOT under `Player/Camera2D/HUD`. That
## Control is world-space at the camera's zoom, and a "full-screen" rect placed there would
## be a small square painted onto the ground next to the player. Being the last child of the
## CanvasLayer is also what puts it over the hotbar and the panels, which is the point of a
## flash.
##
## ONE INSTANCE, REUSED, NEVER FREED. A flash fires on every level-up and on every hit taken,
## which is often enough that a node per flash would be a visible line on the orphan counter.
## `_get_flash()` finds the existing rect or creates it once; `flash()` restarts its tween in
## place. The rect is fully transparent and MOUSE_FILTER_IGNORE at rest, so an idle one is
## invisible and un-clickable rather than merely cheap.

const HOST_PATH := "Main/UI"
const NODE_NAME := "ScreenFlash"

## Fraction of the total duration spent ramping up. Short: a flash that fades *in* reads as a
## screen tint, and a tint reads as something being wrong.
const RISE_FRACTION := 0.18

var _tween: Tween


## Flashes the screen. `source` is only used to reach the scene tree. Returns the rect, or
## null when there is no `Main/UI` to host it (a unit test, or a scene that is not the game).
static func flash(source: Node, colour: Color, peak_alpha: float, duration: float) -> ScreenFlash:
	if source == null or not source.is_inside_tree() or duration <= 0.0 or peak_alpha <= 0.0:
		return null

	var rect := _get_flash(source)
	if rect == null:
		return null

	rect._play(colour, peak_alpha, duration)
	return rect


static func _get_flash(source: Node) -> ScreenFlash:
	var tree := source.get_tree()
	if tree == null:
		return null

	var host: Node = tree.get_root().get_node_or_null(HOST_PATH)
	if host == null:
		return null

	var existing := host.get_node_or_null(NODE_NAME)
	if existing is ScreenFlash:
		return existing as ScreenFlash

	var rect := ScreenFlash.new()
	rect.name = NODE_NAME
	rect._configure()
	host.add_child(rect)
	return rect


func _configure() -> void:
	# Anchored, never sized in pixels: the window is 1920x1080 with stretch disabled, so a
	# hardcoded viewport dimension here would leave a visible unflashed margin the moment the
	# window grew. See the layout note in CLAUDE.md.
	set_anchors_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	color = Color(1.0, 1.0, 1.0, 0.0)
	# Never blocks a click even while opaque, and never eats a keypress.
	z_index = 100


func _play(colour: Color, peak_alpha: float, duration: float) -> void:
	if _tween != null and _tween.is_valid():
		_tween.kill()

	color = Color(colour.r, colour.g, colour.b, 0.0)

	var rise := duration * RISE_FRACTION
	_tween = create_tween()
	_tween.tween_property(self, "color:a", peak_alpha, rise) \
		.set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_OUT)
	_tween.tween_property(self, "color:a", 0.0, duration - rise) \
		.set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN)
