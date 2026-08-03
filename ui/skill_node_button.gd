extends PanelContainer
class_name SkillNodeButton

## One card in the skill panel. Built entirely in code because the tree is
## data-driven — the panel instances one of these per Skill in SkillTree.order,
## so a .tscn would have to be kept in sync with the definitions by hand.

signal node_hovered(skill_id: String)
signal node_pressed(skill_id: String)

enum State { LOCKED, AVAILABLE, TAKEN }

## Base metrics, all pre-scale. The card is laid out for UiTheme.REFERENCE_EDGE and
## re-derived for the real viewport in _apply_scale(); nothing below is a pixel
## count that reaches the screen unmultiplied.
const CARD_HEIGHT := 74
const ICON_SIZE := 34
const PAD_H := 8
const PAD_V := 6
const ROW_GAP := 8
## Reserved width for the point price. Two digits' worth — the tree tops out at 5.
const COST_WIDTH := 14

## Card background. Darker than the panel behind it so the border colour reads.
const BG_LOCKED := Color("1c1f26")
const BG_AVAILABLE := Color("262c38")
const BG_TAKEN := Color("2f3a2c")

## Aliases onto the shared palette. Kept as names because `refresh()` reads them
## per state and the state table is easier to follow with them spelled out.
const TEXT_BRIGHT := UiTheme.COLOR_TEXT
const TEXT_DIM := UiTheme.COLOR_TEXT_DIM

var skill: Skill
var state: int = State.LOCKED

## Set while the player has a point to spend on this node — drives the brighter
## border that separates "you could buy this now" from "you have met its
## requirements but are out of points".
var affordable := false

var _icon: TextureRect
var _name_label: Label
var _summary_label: Label
## The point price, pinned to the right edge of the card. Skills cost tier+1 points
## (`gather-7p4`), so this is the only place the depth-pricing is visible while the
## player is choosing — the panel's header shows the bank, not the price.
var _cost_label: Label
var _branch_color: Color

## Held so _apply_scale() can re-reach the padding and the row gap on a resize.
var _margin: MarginContainer
var _row: HBoxContainer


func _init(_skill: Skill, branch_color: Color):
	skill = _skill
	_branch_color = branch_color

	custom_minimum_size = Vector2(0, CARD_HEIGHT)
	mouse_filter = Control.MOUSE_FILTER_STOP

	_margin = MarginContainer.new()
	_margin.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(_margin)

	_row = HBoxContainer.new()
	_row.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_margin.add_child(_row)

	_icon = TextureRect.new()
	_icon.texture = GameItems.get_item(skill.icon).get_atlas()
	# The atlas is 16x16 pixel art blown up to 34px; without NEAREST every icon
	# in the panel comes out smeared.
	_icon.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	_icon.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	_icon.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	_icon.custom_minimum_size = Vector2(ICON_SIZE, ICON_SIZE)
	_icon.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	_icon.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_row.add_child(_icon)

	var text := VBoxContainer.new()
	text.add_theme_constant_override("separation", 1)
	text.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	text.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	text.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_row.add_child(text)

	_name_label = Label.new()
	_name_label.text = skill.display_name
	_name_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_name_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	text.add_child(_name_label)

	_summary_label = Label.new()
	_summary_label.text = skill.summary
	_summary_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_summary_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	text.add_child(_summary_label)

	_cost_label = Label.new()
	# Named so it is addressable by node path. The other three children here are not, and
	# an unnamed Control lands under Godot's `@Label@249` auto-name, which `get-state`
	# cannot resolve — so the price was the one part of this card that could be seen on
	# screen and not asserted from a test or the devtools bus.
	_cost_label.name = "Cost"
	_cost_label.text = str(skill.cost())
	_cost_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	_cost_label.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	_cost_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_row.add_child(_cost_label)

	# _init runs before the card is in a tree, so there is no viewport to measure
	# yet and UiTheme falls back to 1.0. _ready() re-applies against the real one.
	_apply_scale()


func _ready():
	mouse_entered.connect(func(): node_hovered.emit(skill.id))
	gui_input.connect(_on_gui_input)

	UiTheme.connect_resize(self, _apply_scale)

	_apply_scale()
	refresh()


## Re-derives the card's type and padding for the current viewport.
##
## These were hardcoded 14/11 px with 8/6 px margins, which is legible in a
## desktop window and unreadable on a phone — and the skill cards are the densest
## text in the game, so this was the single worst offender for "the UI is too
## small on mobile". The card's *height* is deliberately not set here: the panel
## drives that from outside through custom_minimum_size, and two writers would
## fight over it every resize.
func _apply_scale() -> void:
	var factor := UiTheme.scale_for_node(self)

	_name_label.add_theme_font_size_override(
		"font_size", UiTheme.scaled_font(UiTheme.FONT_BODY, factor))
	_summary_label.add_theme_font_size_override(
		"font_size", UiTheme.scaled_font(UiTheme.FONT_SMALL, factor))

	_cost_label.add_theme_font_size_override(
		"font_size", UiTheme.scaled_font(UiTheme.FONT_BODY, factor))
	# A reserved width rather than a shrink-to-fit, so a 1-point card and a 4-point one
	# put their number in the same column and the summaries above them stay aligned.
	_cost_label.custom_minimum_size = Vector2(UiTheme.scaled(COST_WIDTH, factor), 0)

	var icon := UiTheme.scaled(ICON_SIZE, factor)
	_icon.custom_minimum_size = Vector2(icon, icon)

	var pad_h := int(round(UiTheme.scaled(PAD_H, factor)))
	var pad_v := int(round(UiTheme.scaled(PAD_V, factor)))
	_margin.add_theme_constant_override("margin_left", pad_h)
	_margin.add_theme_constant_override("margin_right", pad_h)
	_margin.add_theme_constant_override("margin_top", pad_v)
	_margin.add_theme_constant_override("margin_bottom", pad_v)

	_row.add_theme_constant_override("separation", int(round(UiTheme.scaled(ROW_GAP, factor))))


func _on_gui_input(event: InputEvent) -> void:
	if event is InputEventMouseButton \
			and event.button_index == MOUSE_BUTTON_LEFT \
			and event.is_pressed():
		node_pressed.emit(skill.id)


func set_state(new_state: int, is_affordable: bool) -> void:
	state = new_state
	affordable = is_affordable
	refresh()


func refresh() -> void:
	var style := StyleBoxFlat.new()
	style.set_corner_radius_all(4)
	style.set_border_width_all(2)
	style.content_margin_left = 0

	# The price is spent, not owed, once the node is learned — showing "4" on a taken card
	# reads as an outstanding cost. Hidden rather than blanked so the text column keeps the
	# same width in every state and the cards do not reflow as the tree fills in.
	_cost_label.visible = state != State.TAKEN
	# Gold only when the bank can actually cover it. An AVAILABLE node the player cannot
	# yet afford is the case tiering creates and the flat-cost tree never had, so the price
	# is the thing that has to say so.
	_cost_label.add_theme_color_override(
		"font_color", UiTheme.COLOR_GOLD if affordable else TEXT_DIM.darkened(0.15))

	match state:
		State.TAKEN:
			style.bg_color = BG_TAKEN
			style.border_color = _branch_color
			_icon.modulate = Color.WHITE
			_name_label.add_theme_color_override("font_color", TEXT_BRIGHT)
			_summary_label.add_theme_color_override("font_color", _branch_color)
			_summary_label.text = "Learned"
		State.AVAILABLE:
			style.bg_color = BG_AVAILABLE
			# Only a node you can actually afford right now gets the full-strength
			# border; the rest sit at half so the panel points at what is buyable.
			style.border_color = _branch_color if affordable else _branch_color.darkened(0.45)
			style.set_border_width_all(3 if affordable else 2)
			_icon.modulate = Color.WHITE
			_name_label.add_theme_color_override("font_color", TEXT_BRIGHT)
			_summary_label.add_theme_color_override("font_color", TEXT_DIM)
			_summary_label.text = skill.summary
		_:
			style.bg_color = BG_LOCKED
			style.border_color = Color("343a46")
			_icon.modulate = Color(1, 1, 1, 0.25)
			_name_label.add_theme_color_override("font_color", TEXT_DIM)
			_summary_label.add_theme_color_override("font_color", TEXT_DIM.darkened(0.25))
			_summary_label.text = skill.summary

	add_theme_stylebox_override("panel", style)
