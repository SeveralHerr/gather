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
#
# Endesga 64. The world tiles are drawn from the same ramp (see
# `assets/art/endesga_64_palette.png`), which is the whole reason this palette was
# chosen over inventing one: the UI and the grass are guaranteed to belong to each
# other rather than merely not clashing.
#
# The load-bearing colour is COLOR_INK. In this style every element is separated
# from the world by a thick near-black outline, not by a tint or a shadow gradient
# — lose the outline and saturated chrome over saturated grass turns to mush. That
# is why COLOR_BORDER is now the *same* near-black rather than a mid grey: a
# "border" in this UI is an outline, and the two concepts had no reason to differ.

## The outline every element is drawn with, and the only near-black in the palette.
const COLOR_INK := Color("1b1023")

## Full-screen dim behind an open panel. Deeper and more opaque than the old
## slate one — the panel it sits behind is now light enough to need it.
const COLOR_BACKDROP := Color(0.106, 0.063, 0.137, 0.82)
## The panel body itself.
const COLOR_FRAME := Color("3a4466")
## Recessed areas inside a panel (list backgrounds, detail panes).
const COLOR_INSET := Color("262b44")
## Panel borders and separators — the outline. See COLOR_INK above.
const COLOR_BORDER := COLOR_INK
## Primary and secondary body text.
const COLOR_TEXT := Color("f4f4f4")
const COLOR_TEXT_DIM := Color("8b9bb4")
## Currency, skill points, and the "this one matters" accent.
const COLOR_GOLD := Color("fee761")
## Costs the player cannot afford, and destructive actions.
const COLOR_BAD := Color("e43b44")
## Affordable / available / unlocked.
const COLOR_GOOD := Color("63c74d")
## Neutral highlight — selected hotbar slot, hovered card.
const COLOR_ACCENT := Color("0099db")

## Chrome for controls that sit over the world rather than over a backdrop (the
## touch buttons, the hotbar). Near-opaque on purpose: a translucent fill lets the
## tilemap show through and reads as a bug once everything else is flat colour.
const COLOR_OVERLAY_BG := Color(0.149, 0.169, 0.267, 0.94)
const COLOR_OVERLAY_BORDER := COLOR_INK

## Multiplied into a control while a finger or cursor is holding it down. The
## press *also* moves the control into its own shadow (see SHADOW_SIZE); this only
## has to darken it enough to read as depressed under a finger that is covering it.
const PRESSED_MODULATE := Color(0.74, 0.76, 0.86, 1.0)

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

## Corner radius for panels and for the smaller controls inside them.
##
## **Both are zero and should stay zero.** Pixel art has no arcs: a rounded corner
## is drawn by rasterising a curve, which anti-aliases against whatever is behind
## it and puts soft grey pixels on an edge that every other edge on screen keeps
## hard. They are kept as named constants rather than deleted because six files
## pass them to `set_corner_radius_all()`, and a single non-zero value here is the
## one-line way to evaluate going back.
const RADIUS_PANEL := 0
const RADIUS_CONTROL := 0

## The outline width. Every element is separated from the world by this much
## near-black; see the palette note on COLOR_INK.
const BORDER_WIDTH := 3

## Content margin inside a Button, per side.
##
## Named rather than inlined because `test_hud_toolbar.gd` reasons about it
## explicitly: the toolbar is an HFlowContainer, so this number times two times the
## button count is the difference between the strip fitting a 390px phone and
## wrapping onto a second row. It came down from 8 alongside PAD_PANEL, for the
## same reason.
const BUTTON_PAD := 6

## How far the hard drop shadow falls, before scaling.
##
## `StyleBoxFlat` grows its shadow by `shadow_size` on all four sides and *then*
## displaces it by `shadow_offset`, so setting both to the same number lands the
## shadow flush with the top and left edges and `2 * SHADOW_SIZE` proud of the
## bottom and right ones. That asymmetry is the effect — an offset shadow with no
## blur and no halo. Setting only `shadow_offset` draws nothing: the engine gates
## the whole shadow pass on `shadow_size > 0`.
const SHADOW_SIZE := 3

## Padding inside a panel frame, and the gap between stacked children, pre-scale.
##
## Both came down when the outline went on (18 and 8 before). A 3px ink outline
## already separates two elements from each other; padding that also separated
## them was doing the job twice, and the second copy cost real screen height. It
## is not free budget — `inset_style()` gained an outline on all four sides, so
## every well in a panel grew by `2 * BORDER_WIDTH`, and on a 390x844 phone the
## save-slot panel overflowed until this came back down to pay for it.
const PAD_PANEL := 12
const GAP := 6


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

## The one place a StyleBoxFlat is configured, so no caller has to remember the
## two settings that make a box read as pixel art rather than as a web widget:
## square corners, and `anti_aliased = false`.
##
## That second one is the easy thing to leave out and the hard thing to see. It
## defaults to `true`, and on a square-cornered box the softening it applies is a
## single row of blended pixels around the outline — invisible in a screenshot
## viewed at 100%, obvious the moment the window is scaled or the shot is zoomed,
## and inconsistent with every hard-edged sprite behind it.
##
## The property is `anti_aliasing`, not `anti_aliased`. Getting that wrong does not
## fail to compile and does not fail lint: the assignment raises at runtime, which
## aborts `_flat()` and returns **null**, so every factory below silently hands back
## nothing and every control in the game falls back to Godot's default theme. The
## only thing that caught it was `test_save_slot_ui.gd` noticing a button had
## stopped clearing the touch floor.
static func _flat(fill: Color, outline: Color = COLOR_INK,
		width: int = BORDER_WIDTH, radius: int = RADIUS_CONTROL) -> StyleBoxFlat:
	var style := StyleBoxFlat.new()
	style.bg_color = fill
	style.border_color = outline
	style.set_border_width_all(width)
	style.set_corner_radius_all(radius)
	style.anti_aliasing = false
	return style


## Adds the hard offset drop shadow. See SHADOW_SIZE for why both fields are set
## to the same number.
static func _with_shadow(style: StyleBoxFlat, size: int = SHADOW_SIZE) -> StyleBoxFlat:
	style.shadow_color = COLOR_INK
	style.shadow_size = size
	style.shadow_offset = Vector2(size, size)
	return style


## The outer body of a panel: solid fill, thick outline, square, and casting.
static func frame_style() -> StyleBoxFlat:
	return _with_shadow(_flat(COLOR_FRAME, COLOR_INK, BORDER_WIDTH, RADIUS_PANEL), SHADOW_SIZE * 2)


## A recessed area inside a panel — list backgrounds, detail panes, slot wells.
##
## Deliberately the one element with no shadow of its own: it is *below* the panel
## surface, not floating above it, and a well that casts is a well that reads as a
## card. The outline alone carries it.
static func inset_style() -> StyleBoxFlat:
	return _flat(COLOR_INSET)


## Chrome for a control sitting directly over the world, with no backdrop behind
## it to separate it from the tilemap. `accent` draws the brighter outline the
## touch overlay uses for its primary button and the hotbar uses for the selected
## slot.
##
## The accent variant keeps the ink outline and adds the gold *outside* it as the
## shadow colour, so a selected slot gains a highlight without losing the
## separation from the world that the ink provides.
static func overlay_style(accent: bool = false) -> StyleBoxFlat:
	var style := _flat(COLOR_OVERLAY_BG)
	_with_shadow(style)
	if accent:
		style.shadow_color = COLOR_GOLD
	return style


## Applies the four StyleBoxes a Button draws itself with, so buttons in
## different panels stop looking like they came from different games. `danger`
## tints the destructive variant.
##
## The press is a *movement*, not just a recolour: `pressed` drops the shadow and
## shifts the box down-right by the same amount, so the button visibly travels
## into the hole it was casting into. Content margins move with it, which is what
## carries the label along — a button that changed colour but held still read as
## disabled rather than held.
static func style_button(button: Button, danger: bool = false) -> void:
	# A destructive action is the one thing loud enough to be filled; everything
	# else takes the neutral panel face. Filling every button with the accent puts
	# four saturated blues next to the gold skill-point chip and nothing wins.
	var fill := COLOR_BAD if danger else COLOR_FRAME

	var normal := _flat(fill)
	_with_shadow(normal)
	normal.set_content_margin_all(BUTTON_PAD)

	var hover := normal.duplicate() as StyleBoxFlat
	hover.bg_color = fill.lightened(0.18)

	var pressed := normal.duplicate() as StyleBoxFlat
	pressed.bg_color = fill.darkened(0.22)
	pressed.shadow_size = 0
	pressed.shadow_offset = Vector2.ZERO
	pressed.content_margin_left = 8 + SHADOW_SIZE
	pressed.content_margin_top = 8 + SHADOW_SIZE
	pressed.content_margin_right = maxf(0.0, 8 - SHADOW_SIZE)
	pressed.content_margin_bottom = maxf(0.0, 8 - SHADOW_SIZE)

	var disabled := normal.duplicate() as StyleBoxFlat
	disabled.bg_color = COLOR_INSET
	disabled.shadow_color = Color(COLOR_INK, 0.4)

	button.add_theme_stylebox_override("normal", normal)
	button.add_theme_stylebox_override("hover", hover)
	button.add_theme_stylebox_override("pressed", pressed)
	button.add_theme_stylebox_override("disabled", disabled)
	button.add_theme_color_override("font_color", COLOR_TEXT)
	button.add_theme_color_override("font_disabled_color", COLOR_TEXT_DIM)
