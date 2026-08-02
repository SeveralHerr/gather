extends Control
class_name PanelFrame

## The chrome every full-screen panel in the game shares: a dimming backdrop, a
## centred frame, a title bar with a close button, and the three ways a player
## expects to get back out (the X, the backdrop, Escape).
##
## Every panel used to build this itself, and each one built a slightly different
## subset. None of them built the close button at all — on desktop the only way
## out of the skill tree was to press `K` again, and on a phone, where there is no
## keyboard, the only way out of any panel was to find the same toolbar button
## that opened it and press it a second time. That is the bug this class exists to
## make unrepeatable: a panel gets its close affordance by construction now, not
## by each author remembering.
##
## ## Using it
##
## Build it, fill `content`, then parent it. `setup()` constructs eagerly rather
## than waiting for `_ready()`, so `content` is a valid container the moment it
## returns and the owner does not have to care about tree order:
##
## ```gdscript
## _frame = PanelFrame.new()
## _frame.setup("EXPAND THE ISLAND", Vector2(430, 0))
## _frame.close_requested.connect(close)
## add_child(_frame)
## _frame.content.add_child(my_column)
## ```
##
## The owner keeps ownership of *when* the panel is open — `toggle()` is still
## wired to the InputManager signal by the owner, exactly as before. What moves in
## here is only the chrome and the ways out.
##
## Lives in the UI2 CanvasLayer with its owner. Never parent one under
## `Player/Camera2D/UI`: that Control is world-space at 0.23 scale for the
## diegetic HUD (see CLAUDE.md).

## The player asked to leave, by any of the three routes. The owner decides what
## that means — most call `close()`, but one that has to save state first can.
signal close_requested

## Fired after visibility actually changes, for owners that refresh their content
## lazily rather than on every underlying data change.
signal opened
signal closed

## Base metrics, scaled through UiTheme at build time and again whenever the
## window resizes.
const TITLE_BAR_GAP := 12.0
const CLOSE_BUTTON_BASE := 34.0

## The panel body — `content`'s grandparent. Kept so a resize can re-apply the
## scaled minimum size.
var _frame: PanelContainer
var _margin: MarginContainer
var _title_label: Label
var _close_button: Button
var _column: VBoxContainer
var _scroll: ScrollContainer

## Where the owner puts its own UI. Valid as soon as `setup()` returns.
var content: VBoxContainer

var _title := ""
var _base_min_size := Vector2.ZERO
var _built := false


## Builds the chrome. Call once, before `add_child`. `min_size` is the panel's
## unscaled minimum; pass 0 on an axis to let the content decide it, the way
## `land_purchase_ui.gd` does for height.
func setup(title: String, min_size: Vector2 = Vector2.ZERO) -> void:
	if _built:
		push_error("PanelFrame.setup called twice on '%s'" % name)
		return
	_built = true

	_title = title
	_base_min_size = min_size

	name = "PanelFrame"
	visible = false

	# The root spans the screen so the backdrop can, but it must never be the node
	# that swallows a click — the backdrop below does that, deliberately.
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)

	# Clicking the dim area closes, which is the gesture a phone player reaches for
	# first. It STOPs rather than IGNOREs so that click cannot fall through and
	# swing a pickaxe at whatever happened to be under the panel.
	var backdrop := ColorRect.new()
	backdrop.name = "Backdrop"
	backdrop.color = UiTheme.COLOR_BACKDROP
	backdrop.mouse_filter = Control.MOUSE_FILTER_STOP
	backdrop.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	backdrop.gui_input.connect(_on_backdrop_input)
	add_child(backdrop)

	var center := CenterContainer.new()
	center.name = "Center"
	center.mouse_filter = Control.MOUSE_FILTER_IGNORE
	center.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	add_child(center)

	_frame = PanelContainer.new()
	_frame.name = "Frame"
	_frame.add_theme_stylebox_override("panel", UiTheme.frame_style())
	center.add_child(_frame)

	_margin = MarginContainer.new()
	_margin.name = "Margin"
	_frame.add_child(_margin)

	_column = VBoxContainer.new()
	_column.name = "Column"
	_margin.add_child(_column)

	_column.add_child(_build_title_bar())

	var rule := HSeparator.new()
	rule.name = "Rule"
	_column.add_child(rule)

	# The content scrolls rather than forcing the frame taller than the screen. A
	# ScrollContainer reports a near-zero minimum size instead of propagating its
	# child's, which is exactly what bounds the panel: without it the CenterContainer
	# sizes the frame to whatever the content demands and a dense panel — the skill
	# tree's four columns of cards, the crafting recipe list — grows straight off a
	# phone viewport with no way to reach the bottom of it.
	_scroll = ScrollContainer.new()
	_scroll.name = "Scroll"
	_scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	_scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_AUTO
	_scroll.vertical_scroll_mode = ScrollContainer.SCROLL_MODE_AUTO
	_column.add_child(_scroll)

	# Named, and public, because this is the handle every owner and every devtools
	# `get-state --node .../Content` call addresses.
	content = VBoxContainer.new()
	content.name = "Content"
	content.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	content.size_flags_vertical = Control.SIZE_EXPAND_FILL
	_scroll.add_child(content)

	_apply_scale()


func _build_title_bar() -> Control:
	var bar := HBoxContainer.new()
	bar.name = "TitleBar"

	_title_label = Label.new()
	_title_label.name = "Title"
	_title_label.text = _title
	_title_label.add_theme_color_override("font_color", UiTheme.COLOR_TEXT)
	_title_label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_title_label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	bar.add_child(_title_label)

	_close_button = Button.new()
	# Addressed by name from tests and from the devtools bridge, so it must not be
	# left as a generated @Button@nn that shifts with node count.
	_close_button.name = "CloseButton"
	_close_button.text = "X"
	_close_button.tooltip_text = "Close"
	_close_button.focus_mode = Control.FOCUS_NONE
	UiTheme.style_button(_close_button)
	_close_button.pressed.connect(_on_close_pressed)
	bar.add_child(_close_button)

	return bar


func _ready() -> void:
	if not _built:
		push_error("PanelFrame added to the tree without setup(); it will be empty")
		return

	var vp := get_viewport()
	if vp != null and not vp.size_changed.is_connected(_apply_scale):
		vp.size_changed.connect(_apply_scale)

	# Owners fill `content` *after* parenting the frame, so the clamp computed
	# during setup() saw an empty container. Re-running it when the content reports
	# a new minimum is what lets a panel size to what it actually holds.
	if not content.minimum_size_changed.is_connected(_on_content_resized):
		content.minimum_size_changed.connect(_on_content_resized)

	_apply_scale()


func _on_content_resized() -> void:
	# Deferred: this fires *during* the layout pass that is measuring the content,
	# and writing custom_minimum_size back into that pass re-enters it.
	if not is_node_ready():
		return
	_apply_scale.call_deferred()


## Re-derives every size from the current viewport. Runs at build time (when the
## node may not be in the tree yet, hence UiTheme's 1.0 fallback), on every window
## resize, on open, and whenever the content's own minimum size changes — because
## the project's stretch mode is "disabled", so nothing here scales on its own.
func _apply_scale() -> void:
	if not _built:
		return

	var factor := UiTheme.scale_for_node(self)
	var vp_size := Vector2.ONE * UiTheme.REFERENCE_EDGE * factor

	var pad := int(round(UiTheme.scaled(UiTheme.PAD_PANEL, vp_size)))
	_margin.add_theme_constant_override("margin_left", pad)
	_margin.add_theme_constant_override("margin_right", pad)
	_margin.add_theme_constant_override("margin_top", pad)
	_margin.add_theme_constant_override("margin_bottom", pad)

	_column.add_theme_constant_override("separation", int(round(UiTheme.scaled(UiTheme.GAP, vp_size))))

	_title_label.add_theme_font_size_override("font_size", UiTheme.scaled_font(UiTheme.FONT_TITLE, vp_size))

	# The close button is the one control in here a finger must be able to hit, so
	# it takes the touch floor rather than the plain scale.
	var close_side := UiTheme.scaled_touch(CLOSE_BUTTON_BASE, vp_size)
	_close_button.custom_minimum_size = Vector2(close_side, close_side)
	_close_button.add_theme_font_size_override("font_size", UiTheme.scaled_font(UiTheme.FONT_BODY, vp_size))

	_clamp_to_viewport(factor, float(pad))


## Bounds the panel to the screen it is actually on.
##
## `setup()` takes an *unscaled* minimum size chosen for a desktop window — the
## skill tree asks for 920x494 — and scaling it by `UiTheme`'s factor only ever
## makes it larger. At SCALE_MIN that panel still demands 782 px of width, which a
## portrait phone viewport simply does not have, so the frame would hang off both
## edges with its close button somewhere past the bezel.
##
## The panel therefore gets the *smaller* of what it asked for and what fits, and
## the ScrollContainer takes up the difference. Nothing here is a position — the
## CenterContainer still does the centring; these are sizes only.
func _clamp_to_viewport(factor: float, pad: float) -> void:
	var available := Vector2.ZERO
	if is_inside_tree() and get_viewport() != null:
		available = get_viewport().get_visible_rect().size

	# Outside a tree (headless construction) there is no viewport to clamp against,
	# so the panel keeps its requested size and the clamp becomes a no-op.
	if available.x <= 0.0 or available.y <= 0.0:
		_frame.custom_minimum_size = _base_min_size * factor
		return

	# Leave a margin so the frame never sits flush against the bezel, and so the
	# backdrop stays visibly a backdrop rather than a border.
	var gutter := maxf(pad, UiTheme.scaled(UiTheme.GAP, available)) * 2.0
	var fits := (available - Vector2(gutter, gutter)).max(Vector2(120.0, 120.0))

	var wanted := _base_min_size * factor
	_frame.custom_minimum_size = Vector2(minf(wanted.x, fits.x), minf(wanted.y, fits.y))

	# The scroll viewport is what actually caps the panel's height: a ScrollContainer
	# does not propagate its child's minimum size, so the frame stops growing at
	# whatever is set here and the overflow scrolls instead of running off-screen.
	# Asking the content for its natural height first means a short panel — the land
	# purchase panel passes 0 for height on purpose, letting content decide — still
	# sizes to its content rather than collapsing to the title bar.
	var chrome_height := _frame.size.y - _scroll.size.y
	if chrome_height <= 0.0:
		chrome_height = pad * 2.0 + _close_button.custom_minimum_size.y

	var natural := content.get_combined_minimum_size()
	var room := maxf(fits.y - chrome_height, 80.0)
	_scroll.custom_minimum_size = Vector2(
		minf(maxf(natural.x, wanted.x - pad * 2.0), fits.x - pad * 2.0),
		minf(natural.y, room))


func _on_backdrop_input(event: InputEvent) -> void:
	# Touch and mouse both, and only on release: closing on press would fire while
	# a drag that started on the backdrop is still going.
	var mouse := event as InputEventMouseButton
	if mouse != null and not mouse.pressed and mouse.button_index == MOUSE_BUTTON_LEFT:
		close_requested.emit()
		accept_event()
		return

	var touch := event as InputEventScreenTouch
	if touch != null and not touch.pressed:
		close_requested.emit()
		accept_event()


func _on_close_pressed() -> void:
	close_requested.emit()


func _unhandled_input(event: InputEvent) -> void:
	# Only the panel actually on screen answers Escape, and it marks the event
	# handled so two open panels never close on one press.
	if not visible:
		return
	if event.is_action_pressed("ui_cancel"):
		close_requested.emit()
		get_viewport().set_input_as_handled()


func is_open() -> bool:
	return visible


func open() -> void:
	if visible:
		return
	visible = true
	_apply_scale()
	opened.emit()


func close() -> void:
	if not visible:
		return
	visible = false
	closed.emit()


func toggle() -> void:
	if visible:
		close()
	else:
		open()


## Replaces the title after construction, for a panel whose heading depends on
## what opened it (a chest's name, say).
func set_title(title: String) -> void:
	_title = title
	if _title_label != null:
		_title_label.text = title


## Replaces the unscaled size requested at `setup()`, then re-clamps.
##
## For a panel whose desired size depends on its content rather than being fixed —
## the crafting panel picks a wide two-pane layout or a narrow compact one
## depending on how much room it has. Such a panel used to write
## `_frame.custom_minimum_size` directly, which meant two writers on one property
## and a correctness argument that rested on which `size_changed` handler happened
## to be connected first. Going through here keeps `_clamp_to_viewport()` the only
## writer, so the panel cannot end up larger than the screen no matter what it asks
## for or in what order.
func set_panel_size(min_size: Vector2) -> void:
	if _base_min_size.is_equal_approx(min_size):
		return
	_base_min_size = min_size
	_apply_scale()


## The size the frame actually settled on, after scaling and the viewport clamp.
##
## A panel that adapts its internal layout to the room it has — the crafting panel
## switches between a two-pane and a compact form — has to branch on what it *got*,
## not on what it asked for. Reading it back from here means that decision uses the
## same number the clamp produced.
func panel_size() -> Vector2:
	if _frame == null:
		return Vector2.ZERO
	return _frame.custom_minimum_size
