extends Control
class_name SkillTreeUi

## The skill panel, plus the small HUD badge that tells the player they have a
## point waiting. Built in code from SkillTree's definitions rather than as a
## .tscn: the layout is one column per branch and one card per skill, so a scene
## file would only be a second copy of the data that has to be edited in lockstep.
##
## The chrome is PanelFrame's — backdrop, centred frame, title bar, and the close
## button this panel never had. Before that, the only way out of the skill tree was
## to press `K` a second time, which on a phone means finding the toolbar button
## that opened it. The palette and every size come from UiTheme rather than from a
## private copy of the constants.
##
## Sizes here are dense — four columns of cards and a detail pane — and the project
## runs with `window/stretch/mode = "disabled"`, so a phone reports a genuinely
## smaller viewport and anything typed in as a pixel count renders that much
## smaller. Every font size and pad therefore goes through `UiTheme.scaled*` and is
## re-derived by `_apply_scale()` on every window resize.
##
## Lives in the UI CanvasLayer, not the camera-attached HUD Control — that one is
## in world space at 0.23 scale and is sized for the diegetic HUD, not a full
## screen menu. The HUD badge is the exception to "this file is a panel": it is a
## always-on-screen corner readout and is deliberately not inside the frame.

## Width is deliberate — four columns of cards need it. Height is close to the
## content's natural height so the panel does not open with a band of dead space
## between the last row of cards and the detail pane. Both are pre-scale; the frame
## multiplies them by the viewport factor.
const PANEL_MIN_SIZE := Vector2(920, 494)

## Unscaled metrics for the pieces this file draws itself. Everything shared with
## the other panels (pads, gaps, type sizes) comes from UiTheme instead.
const XP_BAR_SIZE := Vector2(190, 9)
const DETAIL_MIN_HEIGHT := 74.0
const DETAIL_PAD := 10.0
const CONNECTOR_SIZE := Vector2(3, 12)
const BRANCH_GAP := 12.0
const BADGE_WIDTH := 170.0
## Distance from the badge to the two screen edges it hugs. A margin, not a
## position: the badge is anchored to the top-right corner and this insets it.
const BADGE_MARGIN := 14.0
const BADGE_PAD := 6.0

## The dark-gold fill behind the banked-point count. No UiTheme equivalent — it is
## the only "this is currency" tint in the game, and COLOR_INSET behind a gold
## border reads as an ordinary recessed box rather than as a purse.
const COLOR_POINTS_BG := Color(0.16, 0.13, 0.05)

var level_up_manager: LevelUpManager
var input_manager: InputManager

## The shared chrome. Replaces the hand-built _panel_root / backdrop / centre /
## frame / margin stack, and owns the panel's visibility — `is_open()` reads it
## rather than a private flag.
var _frame: PanelFrame

var _column: VBoxContainer
var _header: HBoxContainer
var _branch_columns: HBoxContainer
var _level_label: Label
var _xp_bar: ProgressBar
var _xp_label: Label
var _points_label: Label
var _points_style: StyleBoxFlat
var _detail_box: PanelContainer
var _detail_style: StyleBoxFlat
var _detail_name: Label
var _detail_body: Label
var _detail_status: Label

var _hud_badge: PanelContainer
var _hud_badge_style: StyleBoxFlat
var _hud_badge_label: Label

## skill id -> its card, and skill id -> the connector line above it.
var _cards: Dictionary = {}
var _connectors: Dictionary = {}
## The CenterContainer each connector line sits in. Held only so a resize can
## re-apply its height; the line alone cannot set it, the holder reserves the row.
var _connector_holders: Array[Control] = []
## The fixed gap under each branch tagline, same story.
var _branch_gaps: Array[Control] = []

## Every text control paired with the unscaled font size it was authored at, as
## `[control, base_size]`. `_apply_scale()` walks this instead of the file growing
## a field per label — and, more usefully, a label added later cannot be forgotten
## by the resize handler as long as it is built through `_typed()`.
var _typography: Array[Array] = []

var _hovered_id := ""


func _ready():
	add_to_group("UI")

	# The root is only a container for the badge and the panel; it must not swallow
	# clicks aimed at the world while the panel is closed.
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)

	# Deferred: this panel lives in the UI CanvasLayer, which main.tscn declares before
	# Systems, so LevelUpManager has not registered itself in its group yet. Binding
	# here directly found nothing and the panel came up permanently inert.
	_bind_level_up_manager.call_deferred()


func _bind_level_up_manager() -> void:
	level_up_manager = LevelUpManager.find(self)

	if level_up_manager == null:
		push_error("SkillTreeUi: no LevelUpManager in the scene; the panel will be inert")
		return

	input_manager = get_node_or_null("../../Systems/InputManager") as InputManager

	_build_hud_badge()
	_build_panel()

	level_up_manager.points_changed.connect(_on_points_changed)
	level_up_manager.xp_changed.connect(_on_xp_changed)
	level_up_manager.level_gained.connect(_on_level_gained)

	if input_manager:
		input_manager.toggle_skills.connect(toggle)

	# Nothing here scales on its own — see the stretch-mode note at the top — so a
	# resize has to re-run the whole derivation.
	var viewport := get_viewport()
	if viewport != null and not viewport.size_changed.is_connected(_apply_scale):
		viewport.size_changed.connect(_apply_scale)

	# Deferred: the toolbar is created from main.gd's own _ready(), which runs after
	# this one, so on the first pass the sibling does not exist yet.
	_watch_toolbar.call_deferred()

	_refresh_all()


## Follows the HUD toolbar's size and visibility, because the badge is parked
## underneath it and has to move when it does.
func _watch_toolbar() -> void:
	var parent := get_parent()
	if parent == null:
		return
	var toolbar := parent.get_node_or_null("HudToolbar") as HudToolbar
	if toolbar == null:
		return
	if not toolbar.layout_changed.is_connected(_apply_scale):
		toolbar.layout_changed.connect(_apply_scale)
	_apply_scale()


# --- construction ------------------------------------------------------------

## The corner readout that says a point is banked. Not part of the panel: it is on
## screen whenever the player has something to spend, and it is the only cue that
## a level happened now that levelling no longer seizes the screen.
func _build_hud_badge() -> void:
	_hud_badge = PanelContainer.new()
	_hud_badge.name = "PointsBadge"
	_hud_badge.visible = false
	_hud_badge.mouse_filter = Control.MOUSE_FILTER_IGNORE
	# Anchored to the corner; `_apply_scale()` supplies the inset from it. The
	# offset is derived from the badge's own scaled width, never from a viewport
	# dimension — that is the gather-6fx trap.
	_hud_badge.set_anchors_and_offsets_preset(Control.PRESET_TOP_RIGHT)

	# It sits directly over the tilemap with no backdrop behind it, which is exactly
	# what UiTheme's overlay chrome is for; `accent` gives it the gold border.
	_hud_badge_style = UiTheme.overlay_style(true)
	_hud_badge.add_theme_stylebox_override("panel", _hud_badge_style)

	# FONT_BODY rather than the smaller size this used to hardcode: the badge is
	# read at a glance from across the screen, and on a phone the scale factor
	# bottoms out at UiTheme.SCALE_MIN, so a "small" size here is simply unreadable.
	_hud_badge_label = _typed(Label.new(), UiTheme.FONT_BODY) as Label
	_hud_badge_label.name = "BadgeLabel"
	_hud_badge_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_hud_badge_label.add_theme_color_override("font_color", UiTheme.COLOR_GOLD)
	_hud_badge.add_child(_hud_badge_label)

	add_child(_hud_badge)


func _build_panel() -> void:
	_frame = PanelFrame.new()
	_frame.setup("SKILLS", PANEL_MIN_SIZE)
	# The X, the backdrop and Escape all arrive here as one signal. Routing it
	# through set_open() rather than straight to _frame.close() is what keeps the
	# cursor / disable_input handshake running on every way out, including the two
	# that did not exist before. A close that skipped it would hide the panel and
	# leave the player unable to move — invisible to any visibility check.
	_frame.close_requested.connect(_on_close_requested)
	add_child(_frame)

	# PanelFrame.content is a plain VBoxContainer, valid the moment setup() returns.
	_column = _frame.content

	# The frame's title bar carries the "SKILLS" heading and the separator under it
	# now, so this row is only the progress readout and starts at the level.
	_column.add_child(_build_header())
	_column.add_child(_build_branches())
	_column.add_child(_build_detail())
	_column.add_child(_build_footer())

	_apply_scale()


func _build_header() -> Control:
	_header = HBoxContainer.new()
	_header.name = "Header"

	_level_label = _typed(Label.new(), UiTheme.FONT_BODY) as Label
	_level_label.name = "Level"
	_level_label.add_theme_color_override("font_color", UiTheme.COLOR_TEXT)
	_level_label.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	_header.add_child(_level_label)

	var spacer := Control.new()
	spacer.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_header.add_child(spacer)

	var xp_column := VBoxContainer.new()
	xp_column.name = "Xp"
	xp_column.add_theme_constant_override("separation", 2)
	xp_column.size_flags_vertical = Control.SIZE_SHRINK_CENTER

	_xp_bar = ProgressBar.new()
	_xp_bar.name = "XpBar"
	_xp_bar.show_percentage = false
	_xp_bar.add_theme_stylebox_override("background", _bar_style(UiTheme.COLOR_INSET))
	_xp_bar.add_theme_stylebox_override("fill", _bar_style(UiTheme.COLOR_ACCENT))
	xp_column.add_child(_xp_bar)

	_xp_label = _typed(Label.new(), UiTheme.FONT_SMALL) as Label
	_xp_label.name = "XpLabel"
	_xp_label.add_theme_color_override("font_color", UiTheme.COLOR_TEXT_DIM)
	_xp_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	xp_column.add_child(_xp_label)

	_header.add_child(xp_column)

	var points_box := PanelContainer.new()
	points_box.name = "Points"
	points_box.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	# Held as a field because the content margin is a size like any other and has to
	# be re-derived on a resize; a StyleBox edited in place re-lays-out its owner.
	_points_style = StyleBoxFlat.new()
	_points_style.bg_color = COLOR_POINTS_BG
	_points_style.border_color = UiTheme.COLOR_GOLD
	_points_style.set_border_width_all(UiTheme.BORDER_WIDTH)
	_points_style.set_corner_radius_all(UiTheme.RADIUS_CONTROL)
	points_box.add_theme_stylebox_override("panel", _points_style)

	_points_label = _typed(Label.new(), UiTheme.FONT_BODY) as Label
	_points_label.name = "PointsLabel"
	_points_label.add_theme_color_override("font_color", UiTheme.COLOR_GOLD)
	points_box.add_child(_points_label)
	_header.add_child(points_box)

	return _header


func _bar_style(color: Color) -> StyleBoxFlat:
	var style := StyleBoxFlat.new()
	style.bg_color = color
	style.set_corner_radius_all(2)
	return style


func _build_branches() -> Control:
	_branch_columns = HBoxContainer.new()
	_branch_columns.name = "Branches"
	_branch_columns.size_flags_vertical = Control.SIZE_EXPAND_FILL

	for branch in SkillTree.BRANCHES:
		_branch_columns.add_child(_build_branch_column(branch))

	return _branch_columns


func _build_branch_column(branch: String) -> Control:
	var branch_color: Color = SkillTree.BRANCH_COLORS[branch]

	var column := VBoxContainer.new()
	column.name = "Branch_%s" % branch
	# Deliberately 0: the connectors are what separate the cards, and a separation
	# on top of them would break the column's read as one chain.
	column.add_theme_constant_override("separation", 0)
	column.size_flags_horizontal = Control.SIZE_EXPAND_FILL

	var title := _typed(Label.new(), UiTheme.FONT_BODY) as Label
	title.name = "Title"
	title.text = branch.to_upper()
	title.add_theme_color_override("font_color", branch_color)
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	column.add_child(title)

	var tagline := _typed(Label.new(), UiTheme.FONT_SMALL) as Label
	tagline.name = "Tagline"
	tagline.text = SkillTree.BRANCH_TAGLINES[branch]
	tagline.add_theme_color_override("font_color", UiTheme.COLOR_TEXT_DIM)
	tagline.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	tagline.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	column.add_child(tagline)

	var gap := Control.new()
	gap.name = "Gap"
	_branch_gaps.append(gap)
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
	tail.name = "Tail"
	tail.size_flags_vertical = Control.SIZE_EXPAND_FILL
	column.add_child(tail)

	return column


## The short vertical line drawn between two cards in a branch. It lights up once
## the node above it is learned, so a column reads as a chain rather than a list.
func _build_connector(below_skill_id: String, branch_color: Color) -> Control:
	var holder := CenterContainer.new()
	holder.name = "Link_%s" % below_skill_id
	holder.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_connector_holders.append(holder)

	var line := ColorRect.new()
	line.name = "Line"
	line.color = branch_color.darkened(0.65)
	line.mouse_filter = Control.MOUSE_FILTER_IGNORE
	holder.add_child(line)

	_connectors[below_skill_id] = line
	return holder


func _build_detail() -> Control:
	_detail_box = PanelContainer.new()
	_detail_box.name = "Detail"

	_detail_style = UiTheme.inset_style()
	_detail_box.add_theme_stylebox_override("panel", _detail_style)

	var column := VBoxContainer.new()
	column.name = "DetailColumn"
	column.add_theme_constant_override("separation", 2)
	_detail_box.add_child(column)

	_detail_name = _typed(Label.new(), UiTheme.FONT_BODY) as Label
	_detail_name.name = "DetailName"
	column.add_child(_detail_name)

	_detail_body = _typed(Label.new(), UiTheme.FONT_SMALL) as Label
	_detail_body.name = "DetailBody"
	_detail_body.add_theme_color_override("font_color", UiTheme.COLOR_TEXT_DIM)
	_detail_body.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	column.add_child(_detail_body)

	_detail_status = _typed(Label.new(), UiTheme.FONT_SMALL) as Label
	_detail_status.name = "DetailStatus"
	column.add_child(_detail_status)

	return _detail_box


func _build_footer() -> Control:
	# The frame now carries an X, the backdrop closes on a tap and Escape works, so
	# the footer names all three rather than only the key a phone does not have.
	var footer := _typed(Label.new(), UiTheme.FONT_SMALL) as Label
	footer.name = "Footer"
	footer.text = "Tap a highlighted skill to spend a point        [K] · [Esc] · tap outside to close"
	footer.add_theme_color_override("font_color", UiTheme.COLOR_TEXT_DIM)
	footer.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	return footer


## Registers a text control's unscaled font size and hands it straight back, so a
## build line stays a single statement.
func _typed(control: Control, base_size: int) -> Control:
	_typography.append([control, base_size])
	return control


# --- sizing ------------------------------------------------------------------

## Re-derives every font size and pad from the current viewport. Runs once at build
## time and again on every window resize. The badge is included: it is outside the
## frame, so PanelFrame's own rescale never reaches it.
func _apply_scale() -> void:
	var factor := UiTheme.scale_for_node(self)
	# UiTheme's helpers take a viewport size rather than a factor, so reconstruct
	# the size that yields exactly this factor. Same round trip panel_frame.gd
	# makes, which is why the frame's chrome and this content grow in step.
	var vp := Vector2.ONE * UiTheme.REFERENCE_EDGE * factor

	for entry in _typography:
		var control: Control = entry[0]
		control.add_theme_font_size_override("font_size", UiTheme.scaled_font(entry[1], vp))

	_scale_badge(vp, factor)

	if _frame == null:
		return

	_column.add_theme_constant_override("separation", int(round(UiTheme.scaled(UiTheme.GAP, vp))))
	_header.add_theme_constant_override("separation", int(round(UiTheme.scaled(UiTheme.GAP * 1.75, vp))))
	_branch_columns.add_theme_constant_override("separation", int(round(UiTheme.scaled(BRANCH_GAP, vp))))

	_xp_bar.custom_minimum_size = XP_BAR_SIZE * factor
	_points_style.set_content_margin_all(UiTheme.scaled(UiTheme.GAP * 0.75, vp))

	_detail_box.custom_minimum_size = Vector2(0, UiTheme.scaled(DETAIL_MIN_HEIGHT, vp))
	_detail_style.set_content_margin_all(UiTheme.scaled(DETAIL_PAD, vp))

	# A card is the thing a finger aims at in this panel, so its height takes the
	# touch floor rather than the plain scale. SkillNodeButton sets the unscaled
	# value in its constructor; this is the same property, re-derived.
	var card_height := UiTheme.scaled_touch(float(SkillNodeButton.CARD_HEIGHT), vp)
	for skill_id in _cards:
		var card: SkillNodeButton = _cards[skill_id]
		card.custom_minimum_size = Vector2(0, card_height)

	var link_height := UiTheme.scaled(CONNECTOR_SIZE.y, vp)
	for holder in _connector_holders:
		holder.custom_minimum_size = Vector2(0, link_height)
	for skill_id in _connectors:
		var line: ColorRect = _connectors[skill_id]
		line.custom_minimum_size = Vector2(UiTheme.scaled(CONNECTOR_SIZE.x, vp), link_height)

	for gap in _branch_gaps:
		gap.custom_minimum_size = Vector2(0, UiTheme.scaled(UiTheme.GAP, vp))


func _scale_badge(vp: Vector2, factor: float) -> void:
	if _hud_badge == null:
		return

	_hud_badge_style.set_content_margin_all(UiTheme.scaled(BADGE_PAD, vp))

	var width := BADGE_WIDTH * factor
	var margin := UiTheme.scaled(BADGE_MARGIN, vp)
	var top := margin + _toolbar_height()
	_hud_badge.custom_minimum_size = Vector2(width, 0)

	# Offsets, not `position`. Anchored top-right the badge's *offsets* are measured
	# from that corner, but `Control.position` is relative to the parent's top-left
	# whatever the anchors say — so writing -(width + margin) into it put the badge
	# 276px off the LEFT edge of a 1920-wide screen, which is where it had been
	# living, unseen, for its whole existence. Nothing here reads a viewport
	# dimension; the anchor supplies the corner (the gather-6fx rule).
	_hud_badge.offset_right = -margin
	_hud_badge.offset_left = -(width + margin)
	_hud_badge.offset_top = top
	# The preset's grow directions (left from the right anchor, down from the top)
	# take the badge out to its own minimum size, so the height comes from the label.
	_hud_badge.offset_bottom = top


## How far down the badge has to start to clear the HUD toolbar, which shares this
## corner. Zero when there is no toolbar (a unit test that builds this panel alone)
## or while it is hidden, so the badge rides back up to the top on a touch device.
func _toolbar_height() -> float:
	var parent := get_parent()
	if parent == null:
		return 0.0
	var toolbar := parent.get_node_or_null("HudToolbar") as HudToolbar
	if toolbar == null:
		return 0.0
	return toolbar.occupied_top_height()


# --- open / close ------------------------------------------------------------

func is_open() -> bool:
	return _frame != null and _frame.is_open()


func toggle() -> void:
	set_open(not is_open())


## The one place visibility changes. Kept as the public entry point because the
## InputManager signal, the devtools `skill_panel` verb and the tests all drive the
## panel through it; the frame only owns *how* it is drawn.
func set_open(open: bool) -> void:
	if _frame == null or _frame.is_open() == open:
		return

	if open:
		_frame.open()
	else:
		_frame.close()

	# Same handshake the inventory and crafting panels use: stop the player walking
	# around behind the menu. Set rather than toggled, so a panel opened twice cannot
	# leave input disabled forever.
	#
	# The cursor is no longer part of it. This used to free it on open and re-capture
	# it on close, which meant every panel was a second writer of a global that
	# player.gd also set — and a panel closing over another one open would re-capture
	# the cursor out from under it. The cursor is now visible for the whole session
	# (player.gd), so there is nothing to hand back.
	if input_manager:
		input_manager.disable_input = open

	if open:
		_hovered_id = ""
		_refresh_all()


## Escape, the X and a tap on the backdrop all land here. The panel no longer
## handles ui_cancel itself — PanelFrame does, and only while it is on screen, so
## two open panels cannot both answer one press.
func _on_close_requested() -> void:
	set_open(false)


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
		_detail_name.add_theme_color_override("font_color", UiTheme.COLOR_TEXT)
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
		_detail_status.add_theme_color_override("font_color", UiTheme.COLOR_TEXT_DIM)
	elif level_up_manager.points > 0:
		_detail_status.text = "Costs 1 point — click to learn"
		_detail_status.add_theme_color_override("font_color", UiTheme.COLOR_GOLD)
	else:
		_detail_status.text = "Costs 1 point — none banked"
		_detail_status.add_theme_color_override("font_color", UiTheme.COLOR_TEXT_DIM)


func _on_node_pressed(skill_id: String) -> void:
	# Select first, buy second. A finger produces no hover, so on a phone a tap was
	# the only way to read a card at all — and a tap on a locked or unaffordable one
	# used to do nothing whatsoever, leaving the detail pane on whatever the mouse
	# last touched. Selecting unconditionally costs the desktop player nothing:
	# hovering already did exactly this.
	_hovered_id = skill_id

	if not level_up_manager.purchase(skill_id):
		_refresh_detail()
		return

	GameSoundManager.play_sound(GameSoundManager.SoundType.POP)
	_refresh_all()
