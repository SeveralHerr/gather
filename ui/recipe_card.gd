extends PanelContainer
class_name RecipeCard

## One tile in the crafting panel's recipe grid. Built entirely in _init like
## SkillNodeButton, so the grid is a loop over the recipe list rather than a scene
## file that has to be kept in step with it.
##
## Three states, and a locked recipe is shown rather than hidden: a recipe the player
## cannot see is a skill they have no reason to buy, and half the skill tree's nodes
## are recipe unlocks.

signal chosen(product: Types.Item, want_max: bool)

enum State { READY, BLOCKED, LOCKED }

const CARD_SIZE := Vector2(96, 112)

const COLOR_BG := Color("262c38")
const COLOR_BG_LOCKED := Color("1c1f26")
const COLOR_BORDER_LOCKED := Color("343a46")
const COLOR_TEXT := Color("f2f4f8")
const COLOR_TEXT_DIM := Color("7d8494")
const COLOR_SHORT := Color("e05a4f")

var product: Types.Item
var state: int = State.LOCKED

var _accent: Color
var _icon: TextureRect
var _name_label: Label
var _badge: Label
var _selected := false
var _hovered := false


func _init(_product: Types.Item, display_name: String, icon: Texture2D, accent: Color):
	product = _product
	_accent = accent

	custom_minimum_size = CARD_SIZE
	focus_mode = Control.FOCUS_ALL
	mouse_filter = Control.MOUSE_FILTER_STOP

	var margin := MarginContainer.new()
	margin.add_theme_constant_override("margin_left", 6)
	margin.add_theme_constant_override("margin_right", 6)
	margin.add_theme_constant_override("margin_top", 6)
	margin.add_theme_constant_override("margin_bottom", 6)
	add_child(margin)

	var column := VBoxContainer.new()
	column.add_theme_constant_override("separation", 2)
	margin.add_child(column)

	_icon = TextureRect.new()
	_icon.texture = icon
	_icon.custom_minimum_size = Vector2(0, 46)
	_icon.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	_icon.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	_icon.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	column.add_child(_icon)

	_name_label = Label.new()
	_name_label.text = display_name
	_name_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_name_label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	_name_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_name_label.custom_minimum_size = Vector2(0, 30)
	_name_label.add_theme_font_size_override("font_size", 12)
	column.add_child(_name_label)

	_badge = Label.new()
	_badge.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_badge.add_theme_font_size_override("font_size", 11)
	column.add_child(_badge)


func _ready() -> void:
	mouse_entered.connect(func(): _hovered = true; _restyle())
	mouse_exited.connect(func(): _hovered = false; _restyle())
	focus_entered.connect(func(): _hovered = true; _restyle())
	focus_exited.connect(func(): _hovered = false; _restyle())
	gui_input.connect(_on_gui_input)
	_restyle()


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
		# as I can" case is one click rather than click-then-hunt-for-MAX.
		chosen.emit(product, event.shift_pressed)
		accept_event()
	elif event.is_action_pressed("ui_accept"):
		chosen.emit(product, false)
		accept_event()


func _restyle() -> void:
	var style := StyleBoxFlat.new()
	style.set_corner_radius_all(4)
	style.set_content_margin_all(0)

	match state:
		State.LOCKED:
			style.bg_color = COLOR_BG_LOCKED
			style.border_color = COLOR_BORDER_LOCKED
			style.set_border_width_all(2)
			# Dimmed, never silhouetted. These icons are 16px; a black cut-out of one
			# is an unreadable blob, while a faded but legible icon still teaches the
			# player what the thing looks like before they can build it.
			_icon.modulate = Color(1, 1, 1, 0.22)
			_name_label.add_theme_color_override("font_color", COLOR_TEXT_DIM)
			_badge.add_theme_color_override("font_color", COLOR_TEXT_DIM)
		State.BLOCKED:
			style.bg_color = COLOR_BG
			style.border_color = _accent.darkened(0.45)
			style.set_border_width_all(2)
			_icon.modulate = Color(1, 1, 1, 1)
			_name_label.add_theme_color_override("font_color", COLOR_TEXT_DIM)
			_badge.add_theme_color_override("font_color", COLOR_SHORT)
		_:
			style.bg_color = COLOR_BG
			style.border_color = _accent
			# Border width, not size: the card lives in a GridContainer, which owns
			# its children's transforms and fights anything that tweens scale.
			style.set_border_width_all(3 if (_selected or _hovered) else 2)
			_icon.modulate = Color(1, 1, 1, 1)
			_name_label.add_theme_color_override("font_color", COLOR_TEXT)
			_badge.add_theme_color_override("font_color", _accent)

	if _selected and state != State.LOCKED:
		style.bg_color = COLOR_BG.lightened(0.08)

	# Locked cards get no hover response at all - they have to feel inert.
	if _hovered and state != State.LOCKED:
		style.bg_color = style.bg_color.lightened(0.06)

	add_theme_stylebox_override("panel", style)
