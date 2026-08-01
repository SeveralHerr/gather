extends PanelContainer
class_name SkillNodeButton

## One card in the skill panel. Built entirely in code because the tree is
## data-driven — the panel instances one of these per Skill in SkillTree.order,
## so a .tscn would have to be kept in sync with the definitions by hand.

signal node_hovered(skill_id: String)
signal node_pressed(skill_id: String)

enum State { LOCKED, AVAILABLE, TAKEN }

const CARD_HEIGHT := 74
const ICON_SIZE := 34

## Card background. Darker than the panel behind it so the border colour reads.
const BG_LOCKED := Color("1c1f26")
const BG_AVAILABLE := Color("262c38")
const BG_TAKEN := Color("2f3a2c")

const TEXT_BRIGHT := Color("f2f4f8")
const TEXT_DIM := Color("7d8494")

var skill: Skill
var state: int = State.LOCKED

## Set while the player has a point to spend on this node — drives the brighter
## border that separates "you could buy this now" from "you have met its
## requirements but are out of points".
var affordable := false

var _icon: TextureRect
var _name_label: Label
var _summary_label: Label
var _branch_color: Color


func _init(_skill: Skill, branch_color: Color):
	skill = _skill
	_branch_color = branch_color

	custom_minimum_size = Vector2(0, CARD_HEIGHT)
	mouse_filter = Control.MOUSE_FILTER_STOP

	var margin := MarginContainer.new()
	margin.add_theme_constant_override("margin_left", 8)
	margin.add_theme_constant_override("margin_right", 8)
	margin.add_theme_constant_override("margin_top", 6)
	margin.add_theme_constant_override("margin_bottom", 6)
	margin.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(margin)

	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 8)
	row.mouse_filter = Control.MOUSE_FILTER_IGNORE
	margin.add_child(row)

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
	row.add_child(_icon)

	var text := VBoxContainer.new()
	text.add_theme_constant_override("separation", 1)
	text.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	text.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	text.mouse_filter = Control.MOUSE_FILTER_IGNORE
	row.add_child(text)

	_name_label = Label.new()
	_name_label.text = skill.display_name
	_name_label.add_theme_font_size_override("font_size", 14)
	_name_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_name_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	text.add_child(_name_label)

	_summary_label = Label.new()
	_summary_label.text = skill.summary
	_summary_label.add_theme_font_size_override("font_size", 11)
	_summary_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_summary_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	text.add_child(_summary_label)


func _ready():
	mouse_entered.connect(func(): node_hovered.emit(skill.id))
	gui_input.connect(_on_gui_input)
	refresh()


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
