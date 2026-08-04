extends Control
class_name QuestUi

## The quest board panel, on `J` or the TASKS button.
##
## The view half of `systems/quest_log.gd`; it holds no quest state and asks the log for
## everything it draws. Same split as every other panel in the game.
##
## ## What it has to communicate, and why each row looks like it does
##
## A quest card is doing three jobs at once and they are easy to collapse into one another: what
## is being asked, how far along it is, and whether it can be handed in. So each card carries a
## title, a sentence, a progress bar with an exact count beside it, and a button whose *label*
## changes rather than only its enabled state — a greyed button that says "CLAIM" tells a player
## nothing about why they cannot press it.
##
## `HAVE` quests spend the items when claimed, and the button says so before it is pressed. A
## player who watches ten planks vanish without warning will be annoyed exactly once and will not
## trust the board again.
##
## Lives in the `UI` CanvasLayer (screen space). Never under `Player/Camera2D/HUD` — that Control
## is world space at the camera's 8x zoom (see CLAUDE.md).
##
## Nothing here is a raw pixel count: the project runs with `window/stretch/mode = "disabled"`,
## so every size goes through `UiTheme.scaled*` and is re-derived in `_apply_scale()`.

const PANEL_MIN_SIZE := Vector2(500, 0)

const CARD_PAD := 10.0
const CARD_GAP := 8.0
const ROW_GAP := 4.0
const BAR_HEIGHT := 8.0
const CLAIM_BUTTON_WIDTH := 108.0
const CLAIM_BUTTON_HEIGHT := 32.0

## Injected by `TileMapHandler._setup_quest_ui()` before this node enters the tree.
var quest_log: QuestLog
var input_manager: InputManager

var _frame: PanelFrame
var _empty_label: Label
var _cards: VBoxContainer
var _typography: Array[Array] = []

## Card styles are held rather than rebuilt, because a StyleBox's content margin is a size like
## any other and has to be re-derived on a resize.
var _card_styles: Array[StyleBoxFlat] = []


func _ready() -> void:
	add_to_group("UI")

	mouse_filter = Control.MOUSE_FILTER_IGNORE
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)

	if quest_log == null:
		quest_log = QuestLog.find(self)

	_build()

	if input_manager:
		input_manager.toggle_quests.connect(toggle)

	if quest_log != null:
		# Rebuild on a claim, because claiming removes a card and may reveal the one it gated.
		quest_log.quest_claimed.connect(_on_quest_claimed)
		# ...and on the log's coarse progress poll, but only while the panel is open — see
		# `_on_progress_changed`.
		quest_log.progress_changed.connect(_on_progress_changed)

	UiTheme.connect_resize(self, _apply_scale)
	_apply_scale()


# --- construction -------------------------------------------------------------


func _build() -> void:
	_frame = PanelFrame.new()
	_frame.setup("TASKS", PANEL_MIN_SIZE)
	_frame.close_requested.connect(_on_close_requested)
	add_child(_frame)

	var column := _frame.content

	var blurb := _typed(Label.new(), UiTheme.FONT_SMALL) as Label
	blurb.name = "Blurb"
	blurb.text = "Jobs worth doing, and what they pay. New ones appear as you finish these."
	blurb.add_theme_color_override("font_color", UiTheme.COLOR_TEXT_DIM)
	blurb.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	column.add_child(blurb)

	column.add_child(HSeparator.new())

	_cards = VBoxContainer.new()
	_cards.name = "Cards"
	column.add_child(_cards)

	# Shown when the board is empty, which is a real end state — every quest claimed — and not an
	# error. Without it the panel opens on nothing at all and reads as broken.
	_empty_label = _typed(Label.new(), UiTheme.FONT_BODY) as Label
	_empty_label.name = "Empty"
	_empty_label.text = "Every task done. Nothing left to ask of you."
	_empty_label.add_theme_color_override("font_color", UiTheme.COLOR_GOOD)
	_empty_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_empty_label.visible = false
	column.add_child(_empty_label)

	var footer := _typed(Label.new(), UiTheme.FONT_SMALL) as Label
	footer.name = "Footer"
	footer.text = "[J] · [Esc] · tap outside to close"
	footer.add_theme_color_override("font_color", UiTheme.COLOR_TEXT_DIM)
	footer.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	column.add_child(footer)

	_apply_scale()


## Rebuilds every card from the log.
##
## From scratch each time rather than updated in place. The board is short (a handful of offered
## quests) and it is only rebuilt when the panel is open or a claim lands, so there is nothing to
## save by diffing — and a stale card offering a quest that was just claimed is exactly the bug
## that would buy.
func _refresh() -> void:
	if _cards == null:
		return

	for child in _cards.get_children():
		child.queue_free()
	_card_styles.clear()
	# `_typography` holds `[control, size]` pairs for controls that are about to be freed.
	# `UiTheme.apply_typography` skips freed entries rather than raising, but leaving them would
	# grow the list on every refresh; the panel's own labels, built in `_build`, are kept.
	_typography = _typography.filter(func(entry): return is_instance_valid(entry[0]))

	if quest_log == null:
		return

	var offered := quest_log.available()
	_empty_label.visible = offered.is_empty()

	for id in offered:
		_build_card(id)

	_apply_scale()


func _build_card(id: String) -> void:
	var quest: Quest = quest_log.board.get_quest(id)
	if quest == null:
		return

	var progress := quest_log.progress_of(id)
	var complete := quest_log.is_complete(id)

	var card := PanelContainer.new()
	card.name = "Card_%s" % id
	var style := UiTheme.inset_style()
	# A finished task announces itself with its border before anything is read, so a player
	# scanning the panel sees which ones are ready without parsing five progress bars.
	style.border_color = UiTheme.COLOR_GOOD if complete else UiTheme.COLOR_BORDER
	style.set_border_width_all(UiTheme.BORDER_WIDTH)
	card.add_theme_stylebox_override("panel", style)
	_card_styles.append(style)
	_cards.add_child(card)

	var row := HBoxContainer.new()
	row.name = "Row"
	card.add_child(row)

	var text_column := VBoxContainer.new()
	text_column.name = "Text"
	text_column.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	row.add_child(text_column)

	var title := _typed(Label.new(), UiTheme.FONT_BODY) as Label
	title.name = "Title"
	title.text = quest.display_name
	title.add_theme_color_override("font_color", UiTheme.COLOR_GOOD if complete else UiTheme.COLOR_TEXT)
	text_column.add_child(title)

	var description := _typed(Label.new(), UiTheme.FONT_SMALL) as Label
	description.name = "Description"
	description.text = quest.description
	description.add_theme_color_override("font_color", UiTheme.COLOR_TEXT_DIM)
	description.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	text_column.add_child(description)

	var bar := ProgressBar.new()
	bar.name = "Bar"
	bar.show_percentage = false
	bar.min_value = 0.0
	bar.max_value = float(maxi(1, quest.amount))
	bar.value = float(progress)
	# A visible track, not `UiTheme.inset_style()`. The card is already an inset, so an inset bar
	# on top of it is the same colour as its own background — a quest at zero progress showed no
	# bar at all, which reads as a missing element rather than as an empty one. The track is what
	# says how far there is to go.
	var track := StyleBoxFlat.new()
	track.bg_color = UiTheme.COLOR_BORDER
	track.set_corner_radius_all(UiTheme.RADIUS_CONTROL)
	bar.add_theme_stylebox_override("background", track)
	var fill := StyleBoxFlat.new()
	fill.bg_color = UiTheme.COLOR_GOOD if complete else UiTheme.COLOR_ACCENT
	fill.set_corner_radius_all(UiTheme.RADIUS_CONTROL)
	bar.add_theme_stylebox_override("fill", fill)
	text_column.add_child(bar)

	# The exact numbers beside the bar, because a bar alone cannot say "9 of 10" — and the
	# difference between 9 and 10 is the entire question the player has.
	var status := _typed(Label.new(), UiTheme.FONT_SMALL) as Label
	status.name = "Status"
	status.text = "%s   ·   %s" % [_progress_text(quest, progress), _reward_text(quest)]
	status.add_theme_color_override("font_color", UiTheme.COLOR_TEXT_DIM)
	text_column.add_child(status)

	var claim := _typed(Button.new(), UiTheme.FONT_SMALL) as Button
	claim.name = "ClaimButton"
	claim.focus_mode = Control.FOCUS_NONE
	claim.disabled = not complete
	# SHRINK_CENTER, not the default FILL. A Button in an HBoxContainer fills the row's height,
	# and the row is as tall as a three-line description — so the button came out as a 100px slab
	# with "0 / 10" floating in the middle of it, which reads as a panel rather than a control.
	claim.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	# The label carries the state, not just the enabled flag. A greyed "CLAIM" says nothing about
	# why; "6 / 10" says exactly why.
	if complete:
		# Said before it is pressed, never after. A HAVE quest takes the items.
		claim.text = "HAND IN" if quest.consumes() else "CLAIM"
	else:
		claim.text = "%d / %d" % [progress, quest.amount]
	UiTheme.style_button(claim)
	claim.pressed.connect(_on_claim_pressed.bind(id))
	row.add_child(claim)


## "6 of 10 wood" / "day 4 of 7" — worded per kind, because "6 of 10" alone does not say what is
## being counted and the description above it is flavour rather than a spec.
func _progress_text(quest: Quest, progress: int) -> String:
	match quest.kind:
		Quest.Kind.HAVE:
			var item := GameItems.get_item(quest.item)
			var item_name: String = item.name if item != null else "items"
			return "%d of %d %s" % [progress, quest.amount, item_name]
		Quest.Kind.KILL:
			return "%d of %d killed" % [progress, quest.amount]
		Quest.Kind.RAID:
			return "%d of %d raids held" % [progress, quest.amount]
		Quest.Kind.DAY:
			return "day %d of %d" % [progress, quest.amount]
		Quest.Kind.LEVEL:
			return "level %d of %d" % [progress, quest.amount]
		Quest.Kind.PARCEL:
			return "%d of %d parcels" % [progress, quest.amount]
	return "%d of %d" % [progress, quest.amount]


func _reward_text(quest: Quest) -> String:
	var parts: Array[String] = []
	if quest.reward_coins > 0:
		parts.append("%d gold" % quest.reward_coins)
	if quest.reward_xp > 0:
		parts.append("%d xp" % quest.reward_xp)
	return "pays " + " + ".join(parts) if not parts.is_empty() else "no reward"


func _typed(control: Control, base_size: int) -> Control:
	_typography.append([control, base_size])
	return control


# --- sizing -------------------------------------------------------------------


func _apply_scale() -> void:
	if _frame == null:
		return

	var factor := UiTheme.scale_for_node(self)

	UiTheme.apply_typography(_typography, factor)

	_cards.add_theme_constant_override("separation", int(round(UiTheme.scaled(CARD_GAP, factor))))

	for style in _card_styles:
		if style != null:
			style.set_content_margin_all(UiTheme.scaled(CARD_PAD, factor))

	for card in _cards.get_children():
		var row := card.get_node_or_null("Row") as HBoxContainer
		if row == null:
			continue
		row.add_theme_constant_override("separation", int(round(UiTheme.scaled(CARD_GAP, factor))))

		var text_column := row.get_node_or_null("Text") as VBoxContainer
		if text_column != null:
			text_column.add_theme_constant_override("separation", int(round(UiTheme.scaled(ROW_GAP, factor))))
			var bar := text_column.get_node_or_null("Bar") as ProgressBar
			if bar != null:
				bar.custom_minimum_size = Vector2(0, UiTheme.scaled(BAR_HEIGHT, factor))

		var claim := row.get_node_or_null("ClaimButton") as Button
		if claim != null:
			# The one control on a card a finger has to hit, so it takes the touch floor rather
			# than the plain scale.
			claim.custom_minimum_size = Vector2(
				UiTheme.scaled(CLAIM_BUTTON_WIDTH, factor),
				UiTheme.scaled_touch(CLAIM_BUTTON_HEIGHT, factor))


# --- open / close -------------------------------------------------------------


func is_open() -> bool:
	return _frame != null and _frame.is_open()


func toggle() -> void:
	set_open(not is_open())


## The one place visibility changes. Public because the InputManager signal, the toolbar button,
## the devtools verb and the tests all drive the panel through it.
func set_open(open: bool) -> void:
	if _frame == null or _frame.is_open() == open:
		return

	if open:
		# Built on open rather than kept live, so a panel nobody has looked at costs nothing.
		_refresh()
		_frame.open()
	else:
		_frame.close()

	# The same handshake the other panels use: stop the player walking around behind the menu.
	# Assigned rather than toggled, so a panel opened twice cannot strand input disabled.
	if input_manager:
		input_manager.disable_input = open


func _on_close_requested() -> void:
	set_open(false)


## Only while the panel is on screen. The log polls twice a second and rebuilding a panel nobody
## is looking at is pure waste — and worse, it would free and rebuild the very Buttons a player
## might be mid-click on if the panel were open in some other build.
func _on_progress_changed() -> void:
	if is_open():
		_refresh()


func _on_quest_claimed(quest: Quest) -> void:
	GameSoundManager.play_sound(GameSoundManager.SoundType.POP)
	# In the world, at the player, like every other reward in the game — the panel is open over
	# the top of it, but the splash is still there when it closes.
	var player := PlayerManager.player
	if player != null:
		SplashText.spawn(
			self, player.global_position, quest.display_name.to_upper(),
			UiTheme.COLOR_GOOD, SplashText.Emphasis.BIG)

	if is_open():
		_refresh()


func _on_claim_pressed(id: String) -> void:
	if quest_log == null:
		return
	# The return value is deliberately ignored for feedback purposes: `claim` refuses only when
	# the quest stopped being claimable between the frame that drew the button and this one (the
	# player dropped the planks into a chest), and the refresh below redraws it as unclaimable,
	# which says so more clearly than an error would.
	quest_log.claim(id)
	_refresh()
