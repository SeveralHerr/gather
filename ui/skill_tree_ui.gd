extends Control
class_name SkillTreeUi

## The skill panel, plus the small HUD badge that tells the player they have a
## point waiting. Built in code from SkillTree's definitions rather than as a
## .tscn: the layout is one column per branch and one card per skill, so a scene
## file would only be a second copy of the data that has to be edited in lockstep.
##
## Lives in the UI2 CanvasLayer, not the camera-attached UI Control — that one is
## in world space at 0.23 scale and is sized for the diegetic HUD, not a full
## screen menu.

## Width is deliberate — four columns of cards need it. Height is close to the
## content's natural height so the panel does not open with a band of dead space
## between the last row of cards and the detail pane.
const PANEL_MIN_SIZE := Vector2(920, 494)

const COLOR_BACKDROP := Color(0.02, 0.03, 0.05, 0.78)
const COLOR_FRAME := Color("161a21")
const COLOR_INSET := Color("11141a")
const COLOR_TEXT := Color("f2f4f8")
const COLOR_TEXT_DIM := Color("7d8494")
const COLOR_POINTS := Color("ffd166")

var level_up_manager: LevelUpManager
var input_manager: InputManager

var _panel_root: Control
var _level_label: Label
var _xp_bar: ProgressBar
var _xp_label: Label
var _points_label: Label
var _detail_name: Label
var _detail_body: Label
var _detail_status: Label

var _hud_badge: PanelContainer
var _hud_badge_label: Label

## skill id -> its card, and skill id -> the connector line above it.
var _cards: Dictionary = {}
var _connectors: Dictionary = {}

var _hovered_id := ""


func _ready():
	add_to_group("UI")

	# The root is only a container for the badge and the panel; it must not swallow
	# clicks aimed at the world while the panel is closed.
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)

	for node in get_tree().get_nodes_in_group("LevelUpManager"):
		# The scene root is in every group, so a type check rather than
		# get_first_node_in_group is the only reliable way to find the real one.
		if node is LevelUpManager:
			level_up_manager = node
			break

	if level_up_manager == null:
		push_error("SkillTreeUi: no LevelUpManager in the scene; the panel will be inert")
		return

	input_manager = get_node_or_null("../../InputManager") as InputManager

	_build_hud_badge()
	_build_panel()

	level_up_manager.points_changed.connect(_on_points_changed)
	level_up_manager.xp_changed.connect(_on_xp_changed)
	level_up_manager.level_gained.connect(_on_level_gained)

	if input_manager:
		input_manager.toggle_skills.connect(toggle)

	_refresh_all()


# --- construction ------------------------------------------------------------

func _build_hud_badge() -> void:
	_hud_badge = PanelContainer.new()
	_hud_badge.name = "PointsBadge"
	_hud_badge.visible = false
	_hud_badge.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_hud_badge.set_anchors_and_offsets_preset(Control.PRESET_TOP_RIGHT)
	_hud_badge.position = Vector2(-190, 14)
	_hud_badge.custom_minimum_size = Vector2(170, 0)

	var style := StyleBoxFlat.new()
	style.bg_color = Color(0.06, 0.07, 0.1, 0.85)
	style.border_color = COLOR_POINTS
	style.set_border_width_all(2)
	style.set_corner_radius_all(4)
	style.set_content_margin_all(6)
	_hud_badge.add_theme_stylebox_override("panel", style)

	_hud_badge_label = Label.new()
	_hud_badge_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_hud_badge_label.add_theme_font_size_override("font_size", 13)
	_hud_badge_label.add_theme_color_override("font_color", COLOR_POINTS)
	_hud_badge.add_child(_hud_badge_label)

	add_child(_hud_badge)


func _build_panel() -> void:
	_panel_root = Control.new()
	# Named rather than left as @Control@19: these are the handles the devtools
	# bridge addresses the panel by, and generated names shift with node count.
	_panel_root.name = "Panel"
	_panel_root.visible = false
	_panel_root.mouse_filter = Control.MOUSE_FILTER_STOP
	_panel_root.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	add_child(_panel_root)

	var backdrop := ColorRect.new()
	backdrop.color = COLOR_BACKDROP
	backdrop.mouse_filter = Control.MOUSE_FILTER_STOP
	backdrop.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_panel_root.add_child(backdrop)

	var center := CenterContainer.new()
	center.mouse_filter = Control.MOUSE_FILTER_IGNORE
	center.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_panel_root.add_child(center)

	var frame := PanelContainer.new()
	frame.custom_minimum_size = PANEL_MIN_SIZE
	frame.add_theme_stylebox_override("panel", _frame_style())
	center.add_child(frame)

	var margin := MarginContainer.new()
	margin.add_theme_constant_override("margin_left", 18)
	margin.add_theme_constant_override("margin_right", 18)
	margin.add_theme_constant_override("margin_top", 14)
	margin.add_theme_constant_override("margin_bottom", 14)
	frame.add_child(margin)

	var column := VBoxContainer.new()
	column.add_theme_constant_override("separation", 10)
	margin.add_child(column)

	column.add_child(_build_header())
	column.add_child(HSeparator.new())
	column.add_child(_build_branches())
	column.add_child(_build_detail())
	column.add_child(_build_footer())


func _frame_style() -> StyleBoxFlat:
	var style := StyleBoxFlat.new()
	style.bg_color = COLOR_FRAME
	style.border_color = Color("2c3340")
	style.set_border_width_all(2)
	style.set_corner_radius_all(6)
	return style


func _build_header() -> Control:
	var header := HBoxContainer.new()
	header.add_theme_constant_override("separation", 14)

	var title := Label.new()
	title.text = "SKILLS"
	title.add_theme_font_size_override("font_size", 22)
	title.add_theme_color_override("font_color", COLOR_TEXT)
	header.add_child(title)

	var spacer := Control.new()
	spacer.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	header.add_child(spacer)

	_level_label = Label.new()
	_level_label.add_theme_font_size_override("font_size", 15)
	_level_label.add_theme_color_override("font_color", COLOR_TEXT)
	_level_label.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	header.add_child(_level_label)

	var xp_column := VBoxContainer.new()
	xp_column.add_theme_constant_override("separation", 2)
	xp_column.size_flags_vertical = Control.SIZE_SHRINK_CENTER

	_xp_bar = ProgressBar.new()
	_xp_bar.custom_minimum_size = Vector2(190, 9)
	_xp_bar.show_percentage = false
	_xp_bar.add_theme_stylebox_override("background", _bar_style(COLOR_INSET))
	_xp_bar.add_theme_stylebox_override("fill", _bar_style(Color("5aa9e6")))
	xp_column.add_child(_xp_bar)

	_xp_label = Label.new()
	_xp_label.add_theme_font_size_override("font_size", 11)
	_xp_label.add_theme_color_override("font_color", COLOR_TEXT_DIM)
	_xp_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	xp_column.add_child(_xp_label)

	header.add_child(xp_column)

	var points_box := PanelContainer.new()
	points_box.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	var points_style := StyleBoxFlat.new()
	points_style.bg_color = Color(0.16, 0.13, 0.05)
	points_style.border_color = COLOR_POINTS
	points_style.set_border_width_all(2)
	points_style.set_corner_radius_all(4)
	points_style.set_content_margin_all(6)
	points_box.add_theme_stylebox_override("panel", points_style)

	_points_label = Label.new()
	_points_label.add_theme_font_size_override("font_size", 14)
	_points_label.add_theme_color_override("font_color", COLOR_POINTS)
	points_box.add_child(_points_label)
	header.add_child(points_box)

	return header


func _bar_style(color: Color) -> StyleBoxFlat:
	var style := StyleBoxFlat.new()
	style.bg_color = color
	style.set_corner_radius_all(2)
	return style


func _build_branches() -> Control:
	var columns := HBoxContainer.new()
	columns.add_theme_constant_override("separation", 12)
	columns.size_flags_vertical = Control.SIZE_EXPAND_FILL

	for branch in SkillTree.BRANCHES:
		columns.add_child(_build_branch_column(branch))

	return columns


func _build_branch_column(branch: String) -> Control:
	var branch_color: Color = SkillTree.BRANCH_COLORS[branch]

	var column := VBoxContainer.new()
	column.name = "Branch_%s" % branch
	column.add_theme_constant_override("separation", 0)
	column.size_flags_horizontal = Control.SIZE_EXPAND_FILL

	var title := Label.new()
	title.text = branch.to_upper()
	title.add_theme_font_size_override("font_size", 15)
	title.add_theme_color_override("font_color", branch_color)
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	column.add_child(title)

	var tagline := Label.new()
	tagline.text = SkillTree.BRANCH_TAGLINES[branch]
	tagline.add_theme_font_size_override("font_size", 10)
	tagline.add_theme_color_override("font_color", COLOR_TEXT_DIM)
	tagline.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	tagline.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	column.add_child(tagline)

	var gap := Control.new()
	gap.custom_minimum_size = Vector2(0, 8)
	column.add_child(gap)

	var first := true
	for skill in level_up_manager.tree.branch_skills(branch):
		if not first:
			column.add_child(_build_connector(skill.id, branch_color))
		first = false

		var card := SkillNodeButton.new(skill, branch_color)
		card.name = "Skill_%s" % skill.id
		card.node_hovered.connect(_on_node_hovered)
		card.node_pressed.connect(_on_node_pressed)
		_cards[skill.id] = card
		column.add_child(card)

	var tail := Control.new()
	tail.size_flags_vertical = Control.SIZE_EXPAND_FILL
	column.add_child(tail)

	return column


## The short vertical line drawn between two cards in a branch. It lights up once
## the node above it is learned, so a column reads as a chain rather than a list.
func _build_connector(below_skill_id: String, branch_color: Color) -> Control:
	var holder := CenterContainer.new()
	holder.custom_minimum_size = Vector2(0, 12)
	holder.mouse_filter = Control.MOUSE_FILTER_IGNORE

	var line := ColorRect.new()
	line.custom_minimum_size = Vector2(3, 12)
	line.color = branch_color.darkened(0.65)
	line.mouse_filter = Control.MOUSE_FILTER_IGNORE
	holder.add_child(line)

	_connectors[below_skill_id] = line
	return holder


func _build_detail() -> Control:
	var box := PanelContainer.new()
	box.custom_minimum_size = Vector2(0, 74)

	var style := StyleBoxFlat.new()
	style.bg_color = COLOR_INSET
	style.set_corner_radius_all(4)
	style.set_content_margin_all(10)
	box.add_theme_stylebox_override("panel", style)

	var column := VBoxContainer.new()
	column.add_theme_constant_override("separation", 2)
	box.add_child(column)

	_detail_name = Label.new()
	_detail_name.add_theme_font_size_override("font_size", 15)
	column.add_child(_detail_name)

	_detail_body = Label.new()
	_detail_body.add_theme_font_size_override("font_size", 12)
	_detail_body.add_theme_color_override("font_color", COLOR_TEXT_DIM)
	_detail_body.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	column.add_child(_detail_body)

	_detail_status = Label.new()
	_detail_status.add_theme_font_size_override("font_size", 12)
	column.add_child(_detail_status)

	return box


func _build_footer() -> Control:
	var footer := Label.new()
	footer.text = "[K] close        Click a highlighted skill to spend a point"
	footer.add_theme_font_size_override("font_size", 11)
	footer.add_theme_color_override("font_color", COLOR_TEXT_DIM)
	footer.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	return footer


# --- open / close ------------------------------------------------------------

func is_open() -> bool:
	return _panel_root != null and _panel_root.visible


func toggle() -> void:
	set_open(not is_open())


func set_open(open: bool) -> void:
	if _panel_root == null or _panel_root.visible == open:
		return

	_panel_root.visible = open

	# Same handshake the inventory and crafting panels use: free the cursor and
	# stop the player walking around behind the menu. Set rather than toggled, so
	# a panel opened twice cannot leave input disabled forever.
	if input_manager:
		input_manager.disable_input = open
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE if open else Input.MOUSE_MODE_CAPTURED

	if open:
		_hovered_id = ""
		_refresh_all()


func _unhandled_input(event: InputEvent) -> void:
	if is_open() and event.is_action_pressed("ui_cancel"):
		set_open(false)
		get_viewport().set_input_as_handled()


# --- state -------------------------------------------------------------------

func _on_points_changed(_points: int) -> void:
	_refresh_all()


func _on_xp_changed(_xp: int, _next_level: int) -> void:
	_refresh_header()


func _on_level_gained(_level: int) -> void:
	# Deliberately does not open the panel. Levels bank as points, so interrupting
	# a fight to force a choice is exactly what this rework removed; the badge is
	# the cue instead.
	_refresh_header()


func _refresh_all() -> void:
	_refresh_header()
	_refresh_cards()
	_refresh_detail()


func _refresh_header() -> void:
	if _hud_badge == null:
		return

	var points := level_up_manager.points
	_hud_badge.visible = points > 0
	_hud_badge_label.text = "%d skill point%s  [K]" % [points, "" if points == 1 else "s"]

	if _level_label == null:
		return

	_level_label.text = "LEVEL %d" % level_up_manager.level
	_xp_bar.max_value = level_up_manager.next_level
	_xp_bar.value = level_up_manager.xp
	_xp_label.text = "%d / %d XP" % [level_up_manager.xp, level_up_manager.next_level]
	_points_label.text = "%d POINT%s" % [points, "" if points == 1 else "S"]


func _refresh_cards() -> void:
	var taken := level_up_manager.taken

	for skill_id in _cards:
		var card: SkillNodeButton = _cards[skill_id]
		var state: int

		if taken.has(skill_id):
			state = SkillNodeButton.State.TAKEN
		elif level_up_manager.is_available(skill_id):
			state = SkillNodeButton.State.AVAILABLE
		else:
			state = SkillNodeButton.State.LOCKED

		card.set_state(state, level_up_manager.can_purchase(skill_id))

	for skill_id in _connectors:
		var skill: Skill = level_up_manager.tree.get_skill(skill_id)
		var branch_color: Color = SkillTree.BRANCH_COLORS[skill.branch]
		var chain_lit := true
		for requirement in skill.requires:
			if not taken.has(requirement):
				chain_lit = false
		_connectors[skill_id].color = branch_color if chain_lit else branch_color.darkened(0.65)


func _on_node_hovered(skill_id: String) -> void:
	_hovered_id = skill_id
	_refresh_detail()


func _refresh_detail() -> void:
	if _detail_name == null:
		return

	if _hovered_id == "" or not level_up_manager.tree.has_skill(_hovered_id):
		_detail_name.text = "Skill tree"
		_detail_name.add_theme_color_override("font_color", COLOR_TEXT)
		_detail_body.text = "Every level banks one point. Hover a skill to read it."
		_detail_status.text = ""
		return

	var skill: Skill = level_up_manager.tree.get_skill(_hovered_id)
	var branch_color: Color = SkillTree.BRANCH_COLORS[skill.branch]

	_detail_name.text = "%s  —  %s" % [skill.display_name, skill.branch]
	_detail_name.add_theme_color_override("font_color", branch_color)
	_detail_body.text = skill.description

	if level_up_manager.taken.has(_hovered_id):
		_detail_status.text = "Learned"
		_detail_status.add_theme_color_override("font_color", branch_color)
		return

	var missing := level_up_manager.tree.missing_requirements(_hovered_id, level_up_manager.taken)
	if not missing.is_empty():
		_detail_status.text = "Requires %s" % ", ".join(missing)
		_detail_status.add_theme_color_override("font_color", COLOR_TEXT_DIM)
	elif level_up_manager.points > 0:
		_detail_status.text = "Costs 1 point — click to learn"
		_detail_status.add_theme_color_override("font_color", COLOR_POINTS)
	else:
		_detail_status.text = "Costs 1 point — none banked"
		_detail_status.add_theme_color_override("font_color", COLOR_TEXT_DIM)


func _on_node_pressed(skill_id: String) -> void:
	if not level_up_manager.purchase(skill_id):
		return

	GameSoundManager.play_sound(GameSoundManager.SoundType.POP)
	_hovered_id = skill_id
	_refresh_all()
