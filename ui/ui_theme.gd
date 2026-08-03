extends RefCounted
class_name UiTheme

## The one place the game's UI colours and metrics live.
##
## Before this, `skill_tree_ui.gd`, `land_purchase_ui.gd` and `crafting_ui.gd`
## each declared their own byte-identical COLOR_BACKDROP / COLOR_FRAME /
## COLOR_INSET / COLOR_TEXT / COLOR_TEXT_DIM block, and `mobile_controls.gd`
## declared a fourth, slightly different one. Three copies agreeing is not
## consistency, it is three chances to drift — recolouring the UI meant editing
## four files and noticing that the fifth existed.
##
## Everything here is `const` or `static`; nothing is ever instantiated. It
## extends RefCounted only because a `class_name` script needs a base, and
## RefCounted is the one that cannot accidentally be added to the tree (see the
## HealthManager note in CLAUDE.md).
##
## ## Sizing
##
## The project runs with `window/stretch/mode = "disabled"` (see `[display]` in
## project.godot), so the viewport is the device's *real* pixel size: a phone
## reports a viewport a fraction of the desktop one's, and nothing scales for
## free. Every size a UI puts on screen therefore has to be derived from the
## current viewport rather than typed in as a pixel count — which is exactly what
## `mobile_controls.gd` already did for its buttons, and what the panels did not
## do at all. `scale_for()` and the `scaled_*` helpers below are that derivation,
## pulled out so the panels and the touch overlay agree.
##
## Do not use these to compute a *position*. Positions come from anchors; a raw
## viewport offset is the bug `gather-6fx` fixed and CLAUDE.md warns about.
##
## **The currency is a factor, not a viewport size.** `scale_for()` and
## `scale_for_node()` are the two ways to obtain one; `scaled()`, `scaled_font()`
## and `scaled_touch()` consume one. The `scaled_*` helpers used to take a
## `Vector2` and reduce it to that same float on the first line, which meant a
## caller holding only a node had to invent a viewport size to feed them —
## `Vector2.ONE * REFERENCE_EDGE * factor`, in six files, each with a comment
## apologising for it. It survived only because `scale_for()`'s clamp happens to
## be idempotent, and `panel_frame.gd` ended up passing the synthetic size to some
## calls and the real one to others without any visible difference (`gather-snn`).
## Taking the factor directly makes that round trip unrepresentable.

# --- palette -----------------------------------------------------------------

## Full-screen dim behind an open panel.
const COLOR_BACKDROP := Color(0.02, 0.03, 0.05, 0.78)
## The panel body itself.
const COLOR_FRAME := Color("161a21")
## Recessed areas inside a panel (list backgrounds, detail panes).
const COLOR_INSET := Color("11141a")
## Panel borders and separators.
const COLOR_BORDER := Color("2c3340")
## Primary and secondary body text.
const COLOR_TEXT := Color("f2f4f8")
const COLOR_TEXT_DIM := Color("7d8494")
## Currency, skill points, and the "this one matters" accent.
const COLOR_GOLD := Color("ffd166")
## Costs the player cannot afford, and destructive actions.
const COLOR_BAD := Color("e2725b")
## Affordable / available / unlocked.
const COLOR_GOOD := Color("6fcf6a")
## Neutral highlight — selected hotbar slot, hovered card.
const COLOR_ACCENT := Color("58a8e0")

## Translucent chrome for controls that sit over the world rather than over a
## backdrop (the touch buttons, the hotbar).
const COLOR_OVERLAY_BG := Color(0.086, 0.102, 0.129, 0.86)
const COLOR_OVERLAY_BORDER := Color(0.49, 0.52, 0.58, 0.55)

## Multiplied into a control while a finger or cursor is holding it down.
const PRESSED_MODULATE := Color(0.62, 0.72, 0.85, 1.0)

# --- metrics -----------------------------------------------------------------

## The viewport short edge the UI's base sizes below were chosen against. A
## device reporting exactly this gets `scale_for() == 1.0`. It matches
## `mobile_controls.gd`'s own reference edge so the panels and the touch overlay
## grow together rather than diverging halfway up the range.
const REFERENCE_EDGE := 720.0

## Bounds on that ratio. A phone must not shrink the chrome into illegibility and
## a 4K desktop window must not inflate it into a cartoon.
const SCALE_MIN := 0.85
const SCALE_MAX := 1.6

## The smallest a control a finger has to hit may ever be, in real pixels, at any
## scale. 48 is the Android accessibility floor and the larger of the two common
## guidelines; the hotbar slots and every close button clear it.
const TOUCH_MIN := 48.0

## Base type sizes, pre-scale. `TITLE` is a panel heading, `BODY` ordinary copy,
## `SMALL` the dim supporting line under it.
const FONT_TITLE := 22
const FONT_BODY := 15
const FONT_SMALL := 12
## No text in the game may render below this many pixels, whatever the scale
## works out to. Below roughly this the pixel font stops being readable at all.
const FONT_MIN := 10

## Corner radius and border width for panels and for the smaller controls inside
## them, so every rounded rectangle in the game shares two numbers.
const RADIUS_PANEL := 8
const RADIUS_CONTROL := 6
const BORDER_WIDTH := 2

## Padding inside a panel frame, and the gap between stacked children, pre-scale.
const PAD_PANEL := 18
const GAP := 8


## The factor every size below is multiplied by, derived from the viewport's
## shortest edge. Falls back to 1.0 for a degenerate viewport, which is what a
## headless test sees before `instantiate_ui()` gives the Control a size.
static func scale_for(viewport_size: Vector2) -> float:
	var shortest := minf(viewport_size.x, viewport_size.y)
	if shortest <= 0.0:
		return 1.0
	return clampf(shortest / REFERENCE_EDGE, SCALE_MIN, SCALE_MAX)


## `scale_for()` for a node already in the tree. Prefer this in `_ready()` and in
## a `size_changed` handler; it saves every caller repeating the viewport lookup
## and the null check that a node outside the tree needs.
static func scale_for_node(node: Node) -> float:
	if node == null or not node.is_inside_tree():
		return 1.0
	var vp := node.get_viewport()
	if vp == null:
		return 1.0
	return scale_for(vp.get_visible_rect().size)


## A base font size at this scale factor, never below FONT_MIN.
##
## `factor` comes from `scale_for()` or `scale_for_node()` — those clamp, this does
## not, so hand it one of theirs rather than a ratio worked out on the spot.
static func scaled_font(base: int, factor: float) -> int:
	return maxi(FONT_MIN, int(round(float(base) * factor)))


## A base length at this scale factor. Use for padding, gaps and icon sizes —
## anything that is a *size*, never an on-screen position.
static func scaled(base: float, factor: float) -> float:
	return base * factor


## A base length at this scale factor, but never allowed below TOUCH_MIN. Use for
## anything a finger is expected to hit: hotbar slots, close buttons, the
## inventory's own slots.
static func scaled_touch(base: float, factor: float) -> float:
	return maxf(TOUCH_MIN, base * factor)


# --- wiring ------------------------------------------------------------------

## Re-runs `handler` whenever the window changes size, once.
##
## The project's stretch mode is "disabled" (see the sizing note above), so nothing
## re-derives itself on a resize for free — every panel has to ask. This was nine
## copies of the same four lines, and the `is_connected` guard is the load-bearing
## one: `_ready()` is not the only place that reaches for it, so connecting
## unguarded stacks a second handler and every size gets applied twice.
static func connect_resize(node: Node, handler: Callable) -> void:
	if node == null or not node.is_inside_tree():
		return
	var vp := node.get_viewport()
	if vp == null or vp.size_changed.is_connected(handler):
		return
	vp.size_changed.connect(handler)


## Applies `factor` to a list of `[control, base_font_size]` pairs.
##
## Four panels keep a `_typography` array of exactly this shape so that adding a
## label is one `append` rather than another line in `_apply_scale()`; this is the
## walk over it that all four were repeating. Entries whose control has since been
## freed are skipped rather than raising — a panel that rebuilds its rows leaves
## stale pairs behind, and a resize weeks later is a bad place to discover it.
static func apply_typography(entries: Array, factor: float) -> void:
	for entry in entries:
		if entry.size() < 2:
			continue
		# `is_instance_valid` before the cast, not after: casting a freed object is
		# itself what raises, so `entry[0] as Control` never gets far enough to return
		# null for one.
		if not is_instance_valid(entry[0]):
			continue
		var control := entry[0] as Control
		if control == null:
			continue
		control.add_theme_font_size_override("font_size", scaled_font(int(entry[1]), factor))


# --- style factories ---------------------------------------------------------

## The outer body of a panel: solid fill, hairline border, rounded.
static func frame_style() -> StyleBoxFlat:
	var style := StyleBoxFlat.new()
	style.bg_color = COLOR_FRAME
	style.border_color = COLOR_BORDER
	style.set_border_width_all(BORDER_WIDTH)
	style.set_corner_radius_all(RADIUS_PANEL)
	return style


## A recessed area inside a panel — list backgrounds, detail panes, slot wells.
static func inset_style() -> StyleBoxFlat:
	var style := StyleBoxFlat.new()
	style.bg_color = COLOR_INSET
	style.set_corner_radius_all(RADIUS_CONTROL)
	return style


## Chrome for a control sitting directly over the world, with no backdrop behind
## it to separate it from the tilemap. `accent` draws the brighter border the
## touch overlay uses for its primary button and the hotbar uses for the selected
## slot.
static func overlay_style(accent: bool = false) -> StyleBoxFlat:
	var style := StyleBoxFlat.new()
	style.bg_color = COLOR_OVERLAY_BG
	style.border_color = COLOR_GOLD if accent else COLOR_OVERLAY_BORDER
	style.set_border_width_all(BORDER_WIDTH + (1 if accent else 0))
	style.set_corner_radius_all(RADIUS_CONTROL)
	return style


## Applies the four StyleBoxes a Button draws itself with, so buttons in
## different panels stop looking like they came from different games. `danger`
## tints the destructive variant.
static func style_button(button: Button, danger: bool = false) -> void:
	var tint := COLOR_BAD if danger else COLOR_ACCENT

	var normal := StyleBoxFlat.new()
	normal.bg_color = COLOR_INSET
	normal.border_color = tint
	normal.set_border_width_all(BORDER_WIDTH)
	normal.set_corner_radius_all(RADIUS_CONTROL)
	normal.set_content_margin_all(8)

	var hover := normal.duplicate() as StyleBoxFlat
	hover.bg_color = tint.darkened(0.55)

	var pressed := normal.duplicate() as StyleBoxFlat
	pressed.bg_color = tint.darkened(0.35)

	var disabled := normal.duplicate() as StyleBoxFlat
	disabled.border_color = COLOR_BORDER

	button.add_theme_stylebox_override("normal", normal)
	button.add_theme_stylebox_override("hover", hover)
	button.add_theme_stylebox_override("pressed", pressed)
	button.add_theme_stylebox_override("disabled", disabled)
	button.add_theme_color_override("font_color", COLOR_TEXT)
	button.add_theme_color_override("font_disabled_color", COLOR_TEXT_DIM)
