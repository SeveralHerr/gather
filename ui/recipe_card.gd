extends PanelContainer
class_name RecipeCard

## One tile in the crafting panel's recipe grid. Built entirely in _init like
## SkillNodeButton, so the grid is a loop over the recipe list rather than a scene
## file that has to be kept in step with it.
##
## Three states, and a locked recipe is shown rather than hidden: a recipe the player
## cannot see is a skill they have no reason to buy, and half the skill tree's nodes
## are recipe unlocks.
##
## Every size here used to be a raw pixel count chosen against one desktop window - a
## 96x112 card carrying 12pt and 11pt text. Picking a recipe is the one thing a player
## does in this panel, which makes the card its primary touch target, so both axes now
## go through `UiTheme.scaled_touch()` and can never land under TOUCH_MIN however small
## the viewport is. `apply_scale()` is public because the owner re-runs it for every
## live card on `size_changed`: the project's stretch mode is "disabled", so nothing in
## here scales on its own.

signal chosen(product: Types.Item, want_max: bool)

enum State { READY, BLOCKED, LOCKED }

## Base metrics, pre-scale, chosen against UiTheme.REFERENCE_EDGE. CARD_SIZE stays
## public because the panel divides the browser width by it to pick a column count.
const CARD_SIZE := Vector2(96, 112)
const CARD_PAD := 6.0
const CARD_GAP := 2.0
const ICON_HEIGHT := 46.0
const NAME_HEIGHT := 30.0

## The card's own surface ramp, and the two colours UiTheme deliberately has no entry
## for: COLOR_INSET is the recessed *well* the grid sits in, so a card painted with it
## reads as a hole rather than as a tile sitting in one. Everything else - the text,
## the dim text, the shortfall red, the inert border - comes from UiTheme.
const COLOR_BG := Color("262c38")
const COLOR_BG_LOCKED := Color("1c1f26")

var product: Types.Item
var state: int = State.LOCKED

var _accent: Color
var _margin: MarginContainer
var _column: VBoxContainer
var _icon: TextureRect
var _name_label: Label
var _badge: Label
var _selected := false
var _hovered := false


func _init(_product: Types.Item, display_name: String, icon: Texture2D, accent: Color):
	product = _product
	_accent = accent

	# Named for the item it shows, so the devtools bridge can address one specific card
	# by path instead of by a generated @PanelContainer@nn that shifts with node count.
	name = "Card" + display_name.replace(" ", "")
	focus_mode = Control.FOCUS_ALL
	mouse_filter = Control.MOUSE_FILTER_STOP

	_margin = MarginContainer.new()
	_margin.name = "Margin"
	add_child(_margin)

	_column = VBoxContainer.new()
	_column.name = "Column"
	_margin.add_child(_column)

	_icon = TextureRect.new()
	_icon.name = "Icon"
	_icon.texture = icon
	_icon.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	_icon.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	_icon.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	_column.add_child(_icon)

	_name_label = Label.new()
	_name_label.name = "Name"
	_name_label.text = display_name
	_name_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_name_label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	_name_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_column.add_child(_name_label)

	_badge = Label.new()
	_badge.name = "Badge"
	_badge.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_column.add_child(_badge)

	# Scale 1.0 is UiTheme's "no viewport yet" fallback, so a card built outside the
	# tree is still sized rather than collapsed to nothing. The owner calls
	# apply_scale() again with the real factor the moment it has one.
	apply_scale(1.0)


func _ready() -> void:
	mouse_entered.connect(func(): _hovered = true; _restyle())
	mouse_exited.connect(func(): _hovered = false; _restyle())
	focus_entered.connect(func(): _hovered = true; _restyle())
	focus_exited.connect(func(): _hovered = false; _restyle())
	gui_input.connect(_on_gui_input)
	_restyle()


## Re-derives every size on the card for a UiTheme scale factor. Called by the owner at
## build time and again on every window resize; safe before the card is in the tree,
## because it only touches nodes _init already made.
func apply_scale(factor: float) -> void:
	# scaled_touch on *both* axes: a recipe card is a finger target first and a label
	# second, so TOUCH_MIN is the floor even on the smallest viewport in range.
	custom_minimum_size = Vector2(
		UiTheme.scaled_touch(CARD_SIZE.x, factor),
		UiTheme.scaled_touch(CARD_SIZE.y, factor))

	var pad := int(round(UiTheme.scaled(CARD_PAD, factor)))
	_margin.add_theme_constant_override("margin_left", pad)
	_margin.add_theme_constant_override("margin_right", pad)
	_margin.add_theme_constant_override("margin_top", pad)
	_margin.add_theme_constant_override("margin_bottom", pad)

	_column.add_theme_constant_override("separation", int(round(UiTheme.scaled(CARD_GAP, factor))))

	_icon.custom_minimum_size = Vector2(0, UiTheme.scaled(ICON_HEIGHT, factor))

	# Body rather than small: the item name is what the player reads to find a recipe,
	# and at the old fixed 12 it was the first text in the game to stop being legible.
	# The height is a minimum, so a name that wraps to two lines grows the card instead
	# of being clipped by it.
	_name_label.custom_minimum_size = Vector2(0, UiTheme.scaled(NAME_HEIGHT, factor))
	_name_label.add_theme_font_size_override(
		"font_size", UiTheme.scaled_font(UiTheme.FONT_BODY, factor))
	_badge.add_theme_font_size_override(
		"font_size", UiTheme.scaled_font(UiTheme.FONT_SMALL, factor))


func set_selected(value: bool) -> void:
	if _selected == value:
		return
	_selected = value
	_restyle()


## `badge` is the line under the name: how many you could make, what you are short of,
## or which skill would unlock it.
func set_state(new_state: int, badge: String) -> void:
	state = new_state
	_badge.text = badge
	_restyle()


func _on_gui_input(event: InputEvent) -> void:
	if state == State.LOCKED:
		return
	if event is InputEventMouseButton and event.pressed and event.button_index == MOUSE_BUTTON_LEFT:
		grab_focus()
		# Shift picks the recipe and fills the quantity, so the common "make as many
		# as I can" case is one click rather than click-then-hunt-for-MAX. A tap on a
		# touchscreen arrives here too, as the emulated mouse button every other
		# Button in the game is also driven by, with shift_pressed false.
		chosen.emit(product, event.shift_pressed)
		accept_event()
	elif event.is_action_pressed("ui_accept"):
		chosen.emit(product, false)
		accept_event()


func _restyle() -> void:
	var style := StyleBoxFlat.new()
	style.set_corner_radius_all(UiTheme.RADIUS_CONTROL)
	style.set_content_margin_all(0)

	match state:
		State.LOCKED:
			style.bg_color = COLOR_BG_LOCKED
			style.border_color = UiTheme.COLOR_BORDER
			style.set_border_width_all(UiTheme.BORDER_WIDTH)
			# Dimmed, never silhouetted. These icons are 16px; a black cut-out of one
			# is an unreadable blob, while a faded but legible icon still teaches the
			# player what the thing looks like before they can build it.
			_icon.modulate = Color(1, 1, 1, 0.22)
			_name_label.add_theme_color_override("font_color", UiTheme.COLOR_TEXT_DIM)
			_badge.add_theme_color_override("font_color", UiTheme.COLOR_TEXT_DIM)
		State.BLOCKED:
			style.bg_color = COLOR_BG
			style.border_color = _accent.darkened(0.45)
			style.set_border_width_all(UiTheme.BORDER_WIDTH)
			_icon.modulate = Color(1, 1, 1, 1)
			_name_label.add_theme_color_override("font_color", UiTheme.COLOR_TEXT_DIM)
			_badge.add_theme_color_override("font_color", UiTheme.COLOR_BAD)
		_:
			style.bg_color = COLOR_BG
			style.border_color = _accent
			# Border width, not size: the card lives in a GridContainer, which owns
			# its children's transforms and fights anything that tweens scale.
			style.set_border_width_all(
				(UiTheme.BORDER_WIDTH + 1) if (_selected or _hovered) else UiTheme.BORDER_WIDTH)
			_icon.modulate = Color(1, 1, 1, 1)
			_name_label.add_theme_color_override("font_color", UiTheme.COLOR_TEXT)
			_badge.add_theme_color_override("font_color", _accent)

	if _selected and state != State.LOCKED:
		style.bg_color = COLOR_BG.lightened(0.08)

	# Locked cards get no hover response at all - they have to feel inert.
	if _hovered and state != State.LOCKED:
		style.bg_color = style.bg_color.lightened(0.06)

	add_theme_stylebox_override("panel", style)
