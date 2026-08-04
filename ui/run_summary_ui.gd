extends Control
class_name RunSummaryUi

## The score card. Shown once, when the boss dies and the run ends.
##
## This is the view half of `systems/run_stats.gd` and holds no run state of its own — it draws
## the summary Dictionary it is handed. Same split as `RaidDirector`/`RaidBanner`, for the same
## reasons.
##
## ## Why the card is the feature
##
## Killing the boss used to change nothing: the world carried on, identical, forever. A number
## at the end is what makes the hours before it mean something and what gives a second run a
## point. So the card is deliberately *slow* — the rows land one at a time and the numbers count
## up — because it is the only moment in the game whose job is to be looked at rather than
## played through.
##
## ## The two ways out
##
## KEEP PLAYING is the safe one and is what Escape, the X and the backdrop all do. NEW RUN
## throws the world away, so it is styled as destructive and asks a second time before it acts —
## a one-click restart sitting under a mouse that is celebrating is a genuinely bad afternoon.
##
## Lives in the `UI` CanvasLayer. Never under `Player/Camera2D/HUD` — that Control is world-space
## at the camera's 8x zoom (see CLAUDE.md).

## The frame's unscaled minimum size. Height is 0: the content decides it, so the card never
## opens with a band of dead space under the buttons.
const PANEL_MIN_SIZE := Vector2(460, 0)

const BUTTON_HEIGHT := 38.0
const INSET_PAD := 12.0
const ROW_GAP := 5.0

## How long each number spends counting up, and the delay between one row landing and the next.
## Twelve rows at 0.08 is under a second of stagger — long enough to read as a tally being
## totted up, short enough that nobody is waiting for it.
const COUNT_TIME := 0.55
const ROW_STAGGER := 0.08

## How far a row slides in from, in unscaled pixels.
const ROW_SLIDE := 18.0

## Injected by `TileMapHandler._setup_run_summary()` before this node enters the tree.
var stats: RunStats
var input_manager: InputManager

var _frame: PanelFrame
var _headline: Label
var _subhead: Label
var _rows: VBoxContainer
var _inset_style: StyleBoxFlat
var _new_run_button: Button
var _keep_button: Button

var _typography: Array[Array] = []

## The value Labels, in display order, so the reveal can walk them.
var _value_labels: Array[Label] = []

## Set once NEW RUN has been pressed a first time. The second press restarts.
var _new_run_armed := false

## Kept so a re-show cannot leave a half-finished reveal running against a new set of rows.
var _reveal_tweens: Array[Tween] = []


func _ready() -> void:
	add_to_group("UI")

	mouse_filter = Control.MOUSE_FILTER_IGNORE
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)

	if stats == null:
		stats = RunStats.find(self)

	_build()

	if stats != null and not stats.run_ended.is_connected(_on_run_ended):
		stats.run_ended.connect(_on_run_ended)

	UiTheme.connect_resize(self, _apply_scale)
	_apply_scale()


# --- construction -------------------------------------------------------------


func _build() -> void:
	_frame = PanelFrame.new()
	_frame.setup("RUN COMPLETE", PANEL_MIN_SIZE)
	# The X, the backdrop and Escape all arrive as this one signal, and all three mean KEEP
	# PLAYING. The destructive option is never on a route the player can take by reflex.
	_frame.close_requested.connect(_on_keep_playing)
	add_child(_frame)

	var column := _frame.content

	_headline = _typed(Label.new(), UiTheme.FONT_TITLE) as Label
	_headline.name = "Headline"
	_headline.text = "THE ISLAND IS YOURS"
	_headline.add_theme_color_override("font_color", UiTheme.COLOR_GOLD)
	_headline.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	column.add_child(_headline)

	_subhead = _typed(Label.new(), UiTheme.FONT_SMALL) as Label
	_subhead.name = "Subhead"
	_subhead.text = "The boss is dead. Here is what the run came to."
	_subhead.add_theme_color_override("font_color", UiTheme.COLOR_TEXT_DIM)
	_subhead.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_subhead.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	column.add_child(_subhead)

	column.add_child(HSeparator.new())

	var inset := PanelContainer.new()
	inset.name = "Numbers"
	# Held as a field: the content margin is a size like any other and has to be re-derived on a
	# resize, and a StyleBox edited in place re-lays-out its owner.
	_inset_style = UiTheme.inset_style()
	inset.add_theme_stylebox_override("panel", _inset_style)
	column.add_child(inset)

	_rows = VBoxContainer.new()
	_rows.name = "Rows"
	inset.add_child(_rows)

	var buttons := HBoxContainer.new()
	buttons.name = "Buttons"
	column.add_child(buttons)

	_keep_button = _typed(Button.new(), UiTheme.FONT_BODY) as Button
	_keep_button.name = "KeepPlayingButton"
	_keep_button.text = "KEEP PLAYING"
	_keep_button.focus_mode = Control.FOCUS_NONE
	_keep_button.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	UiTheme.style_button(_keep_button)
	_keep_button.pressed.connect(_on_keep_playing)
	buttons.add_child(_keep_button)

	_new_run_button = _typed(Button.new(), UiTheme.FONT_BODY) as Button
	_new_run_button.name = "NewRunButton"
	_new_run_button.text = "NEW RUN"
	_new_run_button.focus_mode = Control.FOCUS_NONE
	_new_run_button.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	# Destructive styling, because it is: a new run regenerates the world from scratch.
	UiTheme.style_button(_new_run_button, true)
	_new_run_button.pressed.connect(_on_new_run_pressed)
	buttons.add_child(_new_run_button)

	var footer := _typed(Label.new(), UiTheme.FONT_SMALL) as Label
	footer.name = "Footer"
	footer.text = "A new run keeps your saves. This one stays in its slot."
	footer.add_theme_color_override("font_color", UiTheme.COLOR_TEXT_DIM)
	footer.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	column.add_child(footer)

	_apply_scale()


## One "caption ....... value" line, returning the value Label so the reveal can animate it.
func _add_row(caption: String, value_color: Color) -> Label:
	var row := HBoxContainer.new()
	row.name = "Row_%s" % caption.replace(" ", "")

	var name_label := _typed(Label.new(), UiTheme.FONT_SMALL) as Label
	name_label.text = caption
	name_label.add_theme_color_override("font_color", UiTheme.COLOR_TEXT_DIM)
	row.add_child(name_label)

	var spacer := Control.new()
	spacer.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	row.add_child(spacer)

	var value := _typed(Label.new(), UiTheme.FONT_BODY) as Label
	value.name = "Value"
	value.add_theme_color_override("font_color", value_color)
	value.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	row.add_child(value)

	_rows.add_child(row)
	return value


func _typed(control: Control, base_size: int) -> Control:
	_typography.append([control, base_size])
	return control


# --- sizing -------------------------------------------------------------------


func _apply_scale() -> void:
	if _frame == null:
		return

	var factor := UiTheme.scale_for_node(self)

	UiTheme.apply_typography(_typography, factor)

	_rows.add_theme_constant_override("separation", int(round(UiTheme.scaled(ROW_GAP, factor))))
	_inset_style.set_content_margin_all(UiTheme.scaled(INSET_PAD, factor))

	# The subhead is the widest thing in here, so it is pinned to the frame's width minus its
	# padding — otherwise it sizes itself to one long line and drags the frame out with it.
	_subhead.custom_minimum_size = Vector2(
		UiTheme.scaled(PANEL_MIN_SIZE.x - UiTheme.PAD_PANEL * 2.0, factor), 0)

	var button_height := UiTheme.scaled_touch(BUTTON_HEIGHT, factor)
	_keep_button.custom_minimum_size = Vector2(0, button_height)
	_new_run_button.custom_minimum_size = Vector2(0, button_height)


# --- showing the card ---------------------------------------------------------


func _on_run_ended(summary: Dictionary) -> void:
	show_summary(summary)


## Fills the card from `summary` and opens it. Public so devtools and a test can drive it
## without having to kill a boss first.
func show_summary(summary: Dictionary) -> void:
	_new_run_armed = false
	_new_run_button.text = "NEW RUN"

	_build_rows(summary)

	_frame.open()
	if input_manager:
		# Same handshake every other panel uses: stop the player walking around behind the card.
		# Assigned rather than toggled, so a card opened twice cannot strand input disabled.
		input_manager.disable_input = true

	_reveal()

	Juice.shake(self, Juice.Shake.MEDIUM)
	ScreenFlash.flash(self, Juice.LEVEL_UP_FLASH_COLOR, Juice.LEVEL_UP_FLASH_ALPHA, Juice.LEVEL_UP_FLASH_TIME)
	GameSoundManager.play_sound(GameSoundManager.SoundType.POP)


## Rebuilt from scratch each time rather than updated in place. The card is shown once per run,
## so there is nothing to save by reusing rows — and a stale row from a previous run showing a
## previous run's number is the exact failure this avoids.
func _build_rows(summary: Dictionary) -> void:
	for tween in _reveal_tweens:
		if tween != null and tween.is_valid():
			tween.kill()
	_reveal_tweens.clear()

	for child in _rows.get_children():
		child.queue_free()
	_value_labels.clear()

	# `_typography` holds `[control, size]` pairs for controls that are about to be freed.
	# `UiTheme.apply_typography` skips freed entries rather than raising, but leaving them would
	# grow the list by a dozen every time the card is shown, so the rows' entries are dropped
	# here. The header and button entries built in `_build` are kept.
	_typography = _typography.filter(func(entry): return is_instance_valid(entry[0]))

	_headline.text = "THE ISLAND IS YOURS"
	_subhead.text = "Day %d. The boss is dead — here is what the run came to." % int(summary.get("day", 0))

	# Order is the story: how far, how strong, how rich, then what it cost.
	_spec_row("Days survived", int(summary.get("day", 0)), UiTheme.COLOR_TEXT)
	_spec_row("Level reached", int(summary.get("level", 0)), UiTheme.COLOR_TEXT)
	_spec_row("Skills learned", int(summary.get("skills_learned", 0)), UiTheme.COLOR_ACCENT)
	_spec_row("Gold", int(summary.get("gold", 0)), UiTheme.COLOR_GOLD)
	_spec_row("Parcels bought", int(summary.get("parcels_bought", 0)), UiTheme.COLOR_TEXT)
	_spec_row("Island radius", int(summary.get("land_radius", 0)), UiTheme.COLOR_TEXT)
	_spec_row("Resources gathered", int(summary.get("resources_gathered", 0)), UiTheme.COLOR_GOOD)
	_spec_row("Enemies slain", int(summary.get("enemies_killed", 0)), UiTheme.COLOR_BAD)
	_spec_row("Raids cleared", int(summary.get("raids_cleared", 0)), UiTheme.COLOR_BAD)
	_spec_row("Deaths", int(summary.get("deaths", 0)), UiTheme.COLOR_BAD)

	# Not a number, so it is not counted up — a duration ticking from "0m 00s" reads as a clock
	# that is running rather than as a total that is being tallied.
	var time_label := _add_row("Time played", UiTheme.COLOR_TEXT_DIM)
	time_label.text = RunStats.format_duration(float(summary.get("play_seconds", 0.0)))
	_value_labels.append(time_label)


## A row whose value counts up from zero. The target is stashed on the Label rather than kept in
## a parallel array, so a row and its number cannot get out of step.
func _spec_row(caption: String, value: int, colour: Color) -> void:
	var label := _add_row(caption, colour)
	label.text = "0"
	label.set_meta("target", value)
	_value_labels.append(label)


## Lands the rows one at a time, counting each number up as it arrives.
##
## Rows animate their `modulate` and their `position`, not their size — a size tween re-runs the
## layout of the whole column every frame for every row at once.
func _reveal() -> void:
	var factor := UiTheme.scale_for_node(self)
	var slide := UiTheme.scaled(ROW_SLIDE, factor)

	for i in _value_labels.size():
		var label := _value_labels[i]
		var row := label.get_parent() as Control
		if row == null:
			continue

		row.modulate = Color(1, 1, 1, 0)

		var tween := create_tween()
		_reveal_tweens.append(tween)
		tween.tween_interval(float(i) * ROW_STAGGER)
		tween.set_parallel(true)
		tween.tween_property(row, "modulate:a", 1.0, 0.18)
		tween.tween_property(row, "position:x", row.position.x, 0.28) \
			.from(row.position.x + slide) \
			.set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)

		if label.has_meta("target"):
			var target: int = label.get_meta("target")
			if target > 0:
				tween.tween_method(_write_count.bind(label), 0, target, COUNT_TIME) \
					.set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_OUT)
			else:
				# A zero needs no count-up, and tween_method from 0 to 0 never calls back — so
				# the label would sit on its placeholder forever.
				label.text = "0"


## Bound per label rather than closing over a loop variable: GDScript captures by reference, so
## every row's callback would write into whichever label the loop finished on.
func _write_count(value: int, label: Label) -> void:
	if is_instance_valid(label):
		label.text = str(value)


# --- the two ways out ---------------------------------------------------------


func _on_keep_playing() -> void:
	_frame.close()
	if input_manager:
		input_manager.disable_input = false


## First press arms, second press restarts. See the header: a one-click world wipe under a mouse
## that is celebrating is a bad afternoon, and there is no undo.
func _on_new_run_pressed() -> void:
	if not _new_run_armed:
		_new_run_armed = true
		_new_run_button.text = "SURE? — WIPES THIS WORLD"
		GameSoundManager.play_sound(GameSoundManager.SoundType.POP)
		return

	start_new_run()


## Regenerates the world from scratch.
##
## `reload_current_scene()` rather than a teardown-and-rebuild, and that is a decision rather
## than a shortcut: every save entry in this game is keyed on `get_path()`, and nothing anywhere
## unwinds world generation — the land, the islands, the boss, the tile layers and a dozen
## nodes' worth of state are all built once in `_ready`. Reloading the scene is the only path
## that is guaranteed to produce the same world a fresh boot does, because it *is* a fresh boot.
##
## The saves are untouched: they live in `user://saves/` and this writes nothing. The run that
## just ended is still in whatever slot the player put it in.
func start_new_run() -> void:
	# Released before the reload, not after. The new scene builds a new InputManager, so a flag
	# left up here would be dropped with the old one — harmless today, and exactly the kind of
	# thing that stops being harmless when something starts reading it across a reload.
	if input_manager:
		input_manager.disable_input = false

	var tree := get_tree()
	if tree == null:
		return
	# Deferred: this is called from a Button's `pressed` signal, i.e. from inside the input
	# handling of a node that reloading is about to free.
	tree.reload_current_scene.call_deferred()


func is_open() -> bool:
	return _frame != null and _frame.is_open()
