extends Control
class_name SaveSlotUi

## The save-slot panel: one row per slot, each with its metadata and its own Save,
## Load and Delete. Built in code rather than as a .tscn because main.tscn is shared
## and the layout is three identical rows generated from `SaveLoad.list_slots()` — a
## scene file would only be a second copy of that to keep in sync.
##
## ## Why it exists
##
## Saving was two debug keys, `[` and `]`, writing one anonymous file. A player on a
## phone has neither key, so on touch the game could not be saved or loaded at all,
## and on desktop there was no way to see whether a save existed, when it was made or
## what was in it. This panel is the affordance for all of that.
##
## The chrome is PanelFrame's — backdrop, centred frame, title bar and close button —
## so the three ways out (the X, a tap on the backdrop, Escape) come by construction
## rather than by this file remembering them. The palette and every metric come from
## UiTheme; nothing here is a raw pixel count. The project runs with
## `window/stretch/mode = "disabled"` (see `[display]` in project.godot), so a phone
## reports a genuinely smaller viewport and a size typed in as an integer renders that
## much smaller — `_apply_scale()` re-derives every font size, pad and button height
## from the current viewport and runs again on every window resize.
##
## Lives in the UI CanvasLayer (screen space). It must never be parented under
## `Player/Camera2D/HUD`: that Control is world space at the camera's zoom and sized
## for the diegetic HUD, so a full-screen panel there is drawn into the world and
## scrolls with the camera.
##
## ## What it knows about saving
##
## Only the slot API — `list_slots()`, `save_to_slot()`, `load_from_slot()`,
## `delete_slot()` and the `current_slot` property. It never opens a file, never reads
## the header and never touches the save format; everything it renders comes out of the
## dictionaries `list_slots()` hands back. That is deliberate: the format has already
## been through a path migration and a version stamp, and a UI that parsed it would be
## a second reader to keep in step with the first.

## The frame's unscaled minimum size. Height is 0 — the rows decide it, so the panel
## never opens with a band of dead space under the last slot.
const PANEL_MIN_SIZE := Vector2(430, 0)

## Unscaled height of a row's action buttons. It goes through `scaled_touch()` rather
## than `scaled()`: these are the controls a finger has to hit, and 30px on a phone is
## below the accessibility floor. Delete sitting a mis-tap away from Load is also why
## deleting is a two-step confirm below.
const ACTION_BUTTON_HEIGHT := 30.0

## Unscaled padding inside a slot's recessed box, and the gap between its lines.
const ROW_PAD := 10.0
const ROW_GAP := 4.0

## How long an armed Delete stays armed before it reverts on its own. Long enough to
## read "SURE?" and mean it, short enough that a panel left open does not keep a live
## destructive button waiting under the player's thumb.
const CONFIRM_SECONDS := 4.0

## The face a Delete button wears in each of its two states.
const DELETE_LABEL := "DELETE"
const DELETE_CONFIRM_LABEL := "SURE?"

## The SaveLoad node. Settable so main.gd (or a test) can inject one, and resolved
## defensively below when nothing did.
##
## Deliberately untyped rather than `: SaveLoad`. Two reasons, and the second is the
## one that matters: a statically typed field would make every call here a compile-time
## dependency on that script, and it would make the panel untestable — the tests drive
## it with a stub so the empty / populated / damaged renderings can be asserted without
## writing real files into user:// and without depending on what the real save system
## happens to have on disk. Every call goes through the `has_method` guards below, so a
## missing or half-built save system leaves the panel inert rather than crashing.
var save_load = null

## Resolved from the sibling Systems branch. Null in a unit test that builds this panel
## alone, which every read treats as "nobody to hand the input handshake to".
var input_manager: InputManager

## The shared chrome. Owns the panel's visibility — `is_open()` reads it rather than a
## private flag.
var _frame: PanelFrame

var _column: VBoxContainer
var _blurb: Label
var _slots_column: VBoxContainer
var _status_label: Label
var _confirm_timer: Timer

## One entry per rendered slot, each a Dictionary of that row's controls (see
## `_build_row()`). Held rather than looked up by name because the rows are generated:
## a `find_child("SaveButton")` would return whichever row happened to be first.
var _rows: Array[Dictionary] = []

## The slot whose Delete is currently armed, or 0 for none. Slots are 1-based, so 0 is
## unambiguous. Rendered from here rather than written into the button directly, so a
## refresh that arrives mid-confirm redraws the armed state instead of silently
## disarming it.
var _pending_delete := 0

## Static text controls paired with the unscaled font size they were authored at, as
## `[control, base_size]`. The rows are *not* in here — they are rebuilt, and a list of
## `[freed_control, size]` pairs is exactly the kind of thing that survives long enough
## to crash a resize weeks later. `_apply_scale()` walks `_rows` separately.
var _typography: Array[Array] = []


func _ready() -> void:
	add_to_group("UI")

	# The root only hosts the panel; while closed it must not swallow clicks aimed at
	# the world underneath.
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)

	_confirm_timer = Timer.new()
	_confirm_timer.name = "ConfirmTimer"
	_confirm_timer.one_shot = true
	_confirm_timer.wait_time = CONFIRM_SECONDS
	_confirm_timer.timeout.connect(_on_confirm_timeout)
	add_child(_confirm_timer)

	_build_panel()

	# Nothing here scales on its own — see the stretch-mode note at the top — so a
	# resize has to re-run the whole derivation.
	UiTheme.connect_resize(self, _apply_scale)

	# Deferred: this panel lives in the UI CanvasLayer, which main.tscn declares
	# *before* Systems, so SaveLoad and InputManager have not been readied yet. Binding
	# here directly is what left skill_tree_ui permanently inert until it was deferred
	# too (see the note in that file).
	_bind_systems.call_deferred()

	_refresh()


## Finds the save system and the input manager, unless something already injected them.
func _bind_systems() -> void:
	# Deferred by a frame, so the panel may have been taken out of the tree in between
	# (a test tearing down, a scene change); get_tree() is null there.
	if not is_inside_tree():
		return

	if save_load == null:
		save_load = get_node_or_null("../../Systems/SaveLoad")

	if save_load == null:
		# Last resort, and a type check rather than an index: a group's membership is a
		# fact about today's scene, and this repo has already been bitten by code that
		# indexed `[0]` and reached the scene root instead of the manager it wanted.
		# Note the group named "SaveLoad" holds every *savable* node, not the save
		# system, so this only finds anything if the system ever joins it.
		for node in get_tree().get_nodes_in_group("SaveLoad"):
			var system := node as SaveLoad
			if system != null:
				save_load = system
				break

	if save_load == null:
		push_warning("SaveSlotUi: no SaveLoad in the scene; the panel will list no slots")

	input_manager = get_node_or_null("../../Systems/InputManager") as InputManager
	if input_manager != null and input_manager.has_signal("toggle_saves"):
		# Connected by name rather than as `input_manager.toggle_saves.connect(...)`.
		# The binding that opens this panel is owned elsewhere; a member access would
		# make this file fail to parse in any build where that signal does not exist
		# yet, and a panel that cannot compile is worse than one opened only from the
		# toolbar.
		var callable := Callable(self, "toggle")
		if not input_manager.is_connected("toggle_saves", callable):
			input_manager.connect("toggle_saves", callable)

	_refresh()


# --- construction ------------------------------------------------------------

func _build_panel() -> void:
	_frame = PanelFrame.new()
	_frame.setup("SAVES", PANEL_MIN_SIZE)
	# The X, the backdrop and Escape all arrive here as one signal. Routing it through
	# set_open() rather than straight to _frame.close() is what keeps the disable_input
	# handshake running on every way out — a close that skipped it would hide the panel
	# and leave the player unable to move, which no visibility check would catch.
	_frame.close_requested.connect(_on_close_requested)
	# The slot list is only true as of the last time it was read, and a save can be
	# written by the debug keys while the panel is closed.
	_frame.opened.connect(_on_opened)
	add_child(_frame)

	# PanelFrame.content is a plain VBoxContainer, valid the moment setup() returns.
	_column = _frame.content

	_blurb = _typed(Label.new(), UiTheme.FONT_SMALL) as Label
	_blurb.name = "Blurb"
	_blurb.text = "Each slot holds one world. Saving over a slot replaces it; deleting one cannot be undone."
	_blurb.add_theme_color_override("font_color", UiTheme.COLOR_TEXT_DIM)
	_blurb.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_column.add_child(_blurb)

	_column.add_child(HSeparator.new())

	_slots_column = VBoxContainer.new()
	_slots_column.name = "Slots"
	_column.add_child(_slots_column)

	_status_label = _typed(Label.new(), UiTheme.FONT_SMALL) as Label
	_status_label.name = "Status"
	_status_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_status_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_status_label.add_theme_color_override("font_color", UiTheme.COLOR_TEXT_DIM)
	_column.add_child(_status_label)

	var footer := _typed(Label.new(), UiTheme.FONT_SMALL) as Label
	footer.name = "Footer"
	footer.text = "[Esc] · tap outside to close"
	footer.add_theme_color_override("font_color", UiTheme.COLOR_TEXT_DIM)
	footer.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_column.add_child(footer)

	_apply_scale()


## One slot's row: a recessed box holding a title line, a metadata line and the three
## actions. Returns the Dictionary of controls the render and resize passes address it
## through.
##
## The actions are stacked *under* the text rather than beside it. Three touch-sized
## buttons and a metadata line do not fit across the width a portrait phone leaves once
## the frame's padding is taken out, and the alternative — letting the row scroll
## sideways — hides Delete off the edge of a panel whose whole point is being usable on
## a phone.
func _build_row(slot: int) -> Dictionary:
	var box := PanelContainer.new()
	box.name = "Slot_%d" % slot
	# Held as a field on the row because the content margin is a size like any other
	# and has to be re-derived on a resize; a StyleBox edited in place re-lays-out its
	# owner.
	var style := UiTheme.inset_style()
	box.add_theme_stylebox_override("panel", style)
	_slots_column.add_child(box)

	var column := VBoxContainer.new()
	column.name = "Column"
	box.add_child(column)

	var title := Label.new()
	title.name = "Title"
	title.text = "SLOT %d" % slot
	title.add_theme_color_override("font_color", UiTheme.COLOR_TEXT)
	column.add_child(title)

	var detail := Label.new()
	detail.name = "Detail"
	detail.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	detail.add_theme_color_override("font_color", UiTheme.COLOR_TEXT_DIM)
	column.add_child(detail)

	var actions := HBoxContainer.new()
	actions.name = "Actions"
	column.add_child(actions)

	var save_button := _action_button("SaveButton", "SAVE", false)
	save_button.pressed.connect(_on_save_pressed.bind(slot))
	actions.add_child(save_button)

	var load_button := _action_button("LoadButton", "LOAD", false)
	load_button.pressed.connect(_on_load_pressed.bind(slot))
	actions.add_child(load_button)

	# A gap between Load and Delete, so the destructive button is not flush against the
	# one a player presses on purpose. It expands, which also keeps Delete pinned to the
	# right-hand end of the row whatever the panel's width works out to.
	var spacer := Control.new()
	spacer.name = "Spacer"
	spacer.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	actions.add_child(spacer)

	var delete_button := _action_button("DeleteButton", DELETE_LABEL, true)
	delete_button.pressed.connect(_on_delete_pressed.bind(slot))
	actions.add_child(delete_button)

	return {
		"slot": slot,
		"box": box,
		"style": style,
		"column": column,
		"title": title,
		"detail": detail,
		"actions": actions,
		"save": save_button,
		"load": load_button,
		"delete": delete_button,
	}


func _action_button(node_name: String, label: String, danger: bool) -> Button:
	var button := Button.new()
	# Named, because these are addressed from the tests and from the devtools bridge;
	# a generated @Button@nn shifts with the node count.
	button.name = node_name
	button.text = label
	# The player is steering with the keyboard; a focused button would eat the next
	# Space or Enter and press itself again.
	button.focus_mode = Control.FOCUS_NONE
	UiTheme.style_button(button, danger)
	return button


## Registers a text control's unscaled font size and hands it straight back, so a build
## line stays a single statement. Static chrome only — see the note on `_typography`.
func _typed(control: Control, base_size: int) -> Control:
	_typography.append([control, base_size])
	return control


# --- sizing ------------------------------------------------------------------

## Re-derives every font size, pad and button height from the current viewport. Runs at
## build time, whenever the rows are rebuilt, and on every window resize.
func _apply_scale() -> void:
	if _frame == null:
		return

	# The same factor PanelFrame builds its chrome at, so the two grow in step.
	var factor := UiTheme.scale_for_node(self)

	UiTheme.apply_typography(_typography, factor)

	var gap := int(round(UiTheme.scaled(UiTheme.GAP, factor)))
	_column.add_theme_constant_override("separation", gap)
	_slots_column.add_theme_constant_override("separation", gap)

	# The blurb is the only thing in here wide enough to decide the panel's width, so it
	# is pinned to the frame's own width minus its padding. Without this it would size
	# itself to one very long line and drag the frame out with it.
	#
	# Clamped to what the screen actually has, which land_purchase_ui's version of this
	# line does not need to be: PanelFrame narrows the frame to fit a phone, so pinning
	# the blurb to the *requested* width makes the content wider than the frame it is
	# in, and the ScrollContainer answers that with a horizontal scrollbar — on the one
	# panel whose whole reason for existing is being usable on a phone. The `pad * 4` is
	# PanelFrame's own arithmetic: two pads of gutter outside the frame and two of
	# padding inside it (its gutter is `max(pad, gap)`, and PAD_PANEL is always the
	# larger of the two).
	var pad := UiTheme.scaled(UiTheme.PAD_PANEL, factor)
	var room := INF
	if is_inside_tree() and get_viewport() != null:
		room = get_viewport().get_visible_rect().size.x - pad * 4.0
	_blurb.custom_minimum_size = Vector2(
		minf(UiTheme.scaled(PANEL_MIN_SIZE.x - UiTheme.PAD_PANEL * 2.0, factor), room), 0
	)

	var row_gap := int(round(UiTheme.scaled(ROW_GAP, factor)))
	var button_height := UiTheme.scaled_touch(ACTION_BUTTON_HEIGHT, factor)

	for row in _rows:
		var style: StyleBoxFlat = row["style"]
		style.set_content_margin_all(UiTheme.scaled(ROW_PAD, factor))

		var column: VBoxContainer = row["column"]
		column.add_theme_constant_override("separation", row_gap)

		var actions: HBoxContainer = row["actions"]
		actions.add_theme_constant_override("separation", row_gap)

		var title: Label = row["title"]
		title.add_theme_font_size_override("font_size", UiTheme.scaled_font(UiTheme.FONT_BODY, factor))

		var detail: Label = row["detail"]
		detail.add_theme_font_size_override("font_size", UiTheme.scaled_font(UiTheme.FONT_SMALL, factor))

		for key: String in ["save", "load", "delete"]:
			var button: Button = row[key]
			button.custom_minimum_size = Vector2(0, button_height)
			button.add_theme_font_size_override(
				"font_size", UiTheme.scaled_font(UiTheme.FONT_SMALL, factor))


# --- the save system ---------------------------------------------------------
#
# Every call into SaveLoad goes through one of these. They are guarded rather than
# typed because `save_load` is duck-typed (see the field's own note): a save system
# that is missing, or that predates one of these methods, has to leave the panel inert
# instead of taking the whole UI layer down with it.

func _slot_list() -> Array:
	if save_load == null or not save_load.has_method("list_slots"):
		return []
	var slots: Variant = save_load.list_slots()
	if slots is Array:
		return slots as Array
	return []


func _slot_action(method: String, slot: int) -> bool:
	if save_load == null or not save_load.has_method(method):
		return false
	return bool(save_load.call(method, slot))


## The slot the game is currently playing out of, or 0 if the save system does not say.
## `in` rather than `get()`: a property read on an object that lacks it is an error, and
## this one is optional by design — the panel is legible without the marker.
func _current_slot() -> int:
	if save_load != null and "current_slot" in save_load:
		return int(save_load.current_slot)
	return 0


# --- rendering ---------------------------------------------------------------

## Re-reads the slot list and redraws every row. Cheap — `list_slots()` reads headers,
## not saves — so it runs on open and after every action rather than trying to patch a
## single row, which would miss `current_slot` moving.
func _refresh() -> void:
	if _slots_column == null:
		return

	var slots := _slot_list()
	_ensure_rows(slots)

	if _rows.is_empty():
		_set_status("No save system is available.", UiTheme.COLOR_BAD)
		return

	var current := _current_slot()
	for i in _rows.size():
		var info: Dictionary = slots[i]
		_render_row(_rows[i], info, current)


## Builds (or rebuilds) one row per entry in `slots`. A no-op in the ordinary case,
## where the count has not changed — the rows are rebuilt only when the *number* of
## slots does, so the controls a player is looking at are not replaced underneath a
## press.
func _ensure_rows(slots: Array) -> void:
	if _rows.size() == slots.size():
		return

	for row in _rows:
		var box: Control = row["box"]
		# Removed as well as freed. queue_free() leaves the node parented until the end
		# of the frame, so a rebuild in the same frame would draw both sets of rows.
		_slots_column.remove_child(box)
		box.queue_free()
	_rows.clear()

	# An armed Delete cannot survive its own button being freed.
	_pending_delete = 0

	for i in slots.size():
		var entry: Dictionary = slots[i]
		# Slots are 1-based and the entry states its own number; the index is only the
		# fallback for a stub or a future list that does not.
		_rows.append(_build_row(int(entry.get("slot", i + 1))))

	_apply_scale()


## Draws one row from its slot_info Dictionary.
##
## The three states are branched on *values*, never on key presence: slot_info always
## carries every key, and `exists: false` (an empty slot) and
## `exists: true, readable: false` (a file whose header will not parse) are different
## things that must not render the same. A damaged slot deliberately still offers Save
## and Delete — overwriting or discarding it are the only two things a player can
## usefully do with it — and never offers Load, which is the action that would fail.
func _render_row(row: Dictionary, info: Dictionary, current: int) -> void:
	var slot := int(row["slot"])
	var exists := bool(info.get("exists", false))
	var readable := bool(info.get("readable", false))

	var title: Label = row["title"]
	title.text = "SLOT %d" % slot
	if slot == current and current > 0:
		title.text += "  ·  IN PLAY"
		title.add_theme_color_override("font_color", UiTheme.COLOR_GOLD)
	else:
		title.add_theme_color_override("font_color", UiTheme.COLOR_TEXT)

	var detail: Label = row["detail"]
	if not exists:
		detail.text = "Empty"
		detail.add_theme_color_override("font_color", UiTheme.COLOR_TEXT_DIM)
	elif not readable:
		detail.text = "Damaged — this file cannot be read. Save over it or delete it."
		detail.add_theme_color_override("font_color", UiTheme.COLOR_BAD)
	else:
		detail.text = "Level %d  ·  radius %d  ·  %s" % [
			int(info.get("level", 0)),
			int(info.get("land_radius", 0)),
			format_saved_at(int(info.get("saved_at", 0))),
		]
		detail.add_theme_color_override("font_color", UiTheme.COLOR_TEXT_DIM)

	# Disabled rather than hidden. A row whose buttons come and go changes height and
	# shuffles the ones underneath it, and on a phone that moves the button a thumb is
	# already travelling towards; greyed out says the same thing and stays put.
	var save_button: Button = row["save"]
	save_button.disabled = save_load == null
	save_button.text = "SAVE" if not exists else "OVERWRITE"

	var load_button: Button = row["load"]
	load_button.disabled = not (exists and readable)

	var delete_button: Button = row["delete"]
	delete_button.disabled = not exists
	delete_button.text = DELETE_CONFIRM_LABEL if _pending_delete == slot else DELETE_LABEL


## `saved_at` as a date a player can read, in their own timezone.
##
## `Time.get_datetime_dict_from_unix_time()` answers in UTC, so the offset has to be
## applied by hand — without it a save written at 9am in UTC-7 is labelled 4pm, which
## reads as a bug in the save rather than in the label. Static so the formatting can be
## asserted without standing up the panel.
static func format_saved_at(unix_seconds: int) -> String:
	if unix_seconds <= 0:
		return "date unknown"

	var bias := 0
	var zone := Time.get_time_zone_from_system()
	if zone.has("bias"):
		bias = int(zone["bias"])

	var local := Time.get_datetime_dict_from_unix_time(unix_seconds + bias * 60)
	return "%04d-%02d-%02d %02d:%02d" % [
		int(local["year"]), int(local["month"]), int(local["day"]),
		int(local["hour"]), int(local["minute"]),
	]


## The same confirmation blip the land and skill panels play on a successful action.
##
## Looked up through the group with a type check rather than reached for as the
## `GameSoundManager` autoload, for two reasons. The autoload identifier resolves to a
## node that only exists under the game's own main loop — the headless test runner
## replaces it and instantiates no autoloads, so a test that presses Save would take a
## runtime error mid-handler and, per the runner's known limitation, still be reported
## as a pass. And an index into the group is what CLAUDE.md warns about: `pick_up.gd`
## indexed `[0]` here for years and was reaching the scene root the whole time.
func _play_pop() -> void:
	if not is_inside_tree():
		return
	for node in get_tree().get_nodes_in_group("SoundManager"):
		var manager := node as SoundManager
		if manager != null:
			manager.play_sound(SoundManager.SoundType.POP)
			return


func _set_status(text: String, color: Color) -> void:
	if _status_label == null:
		return
	_status_label.text = text
	_status_label.add_theme_color_override("font_color", color)


# --- actions -----------------------------------------------------------------

func _on_save_pressed(slot: int) -> void:
	# Any other interaction disarms a pending Delete. The confirm is there to stop a
	# mis-tap, and a button left saying "SURE?" while the player does something else is
	# a trap the next tap springs.
	_clear_pending_delete()

	if _slot_action("save_to_slot", slot):
		_set_status("Saved to slot %d." % slot, UiTheme.COLOR_GOOD)
		_play_pop()
	else:
		_set_status("Could not save to slot %d." % slot, UiTheme.COLOR_BAD)

	_refresh()


func _on_load_pressed(slot: int) -> void:
	_clear_pending_delete()

	if not _slot_action("load_from_slot", slot):
		_set_status("Could not load slot %d." % slot, UiTheme.COLOR_BAD)
		_refresh()
		return

	_set_status("Loaded slot %d." % slot, UiTheme.COLOR_GOOD)
	_play_pop()
	_refresh()

	# The world the player asked for is now on screen behind the backdrop, so the panel
	# gets out of the way rather than making them close it to see what they loaded.
	set_open(false)


## Delete is the one irreversible action in this panel, and on a phone it sits a
## fingertip from Load, so the first press only arms it: the button becomes "SURE?" and
## the second press within CONFIRM_SECONDS does the work. It reverts on the timer, on
## any other button in the panel, and on the panel closing.
##
## Deliberately not a second confirmation panel. A modal over a modal is more chrome to
## keep sized and centred than the risk warrants, and it puts the confirm somewhere
## other than where the player's finger already is.
func _on_delete_pressed(slot: int) -> void:
	if _pending_delete != slot:
		_clear_pending_delete()
		_pending_delete = slot
		_set_status("Press again to delete slot %d for good." % slot, UiTheme.COLOR_BAD)
		if _confirm_timer != null and is_inside_tree():
			_confirm_timer.start(CONFIRM_SECONDS)
		_refresh()
		return

	_pending_delete = 0
	if _confirm_timer != null:
		_confirm_timer.stop()

	if _slot_action("delete_slot", slot):
		_set_status("Slot %d deleted." % slot, UiTheme.COLOR_TEXT_DIM)
	else:
		_set_status("Could not delete slot %d." % slot, UiTheme.COLOR_BAD)

	_refresh()


func _clear_pending_delete() -> void:
	if _pending_delete == 0:
		return
	_pending_delete = 0
	if _confirm_timer != null:
		_confirm_timer.stop()
	_refresh()


func _on_confirm_timeout() -> void:
	_clear_pending_delete()


# --- open / close ------------------------------------------------------------

func is_open() -> bool:
	return _frame != null and _frame.is_open()


func toggle() -> void:
	set_open(not is_open())


## open() and close() are thin aliases over set_open(). They exist because the pair is how
## PanelFrame itself names these, and because it is how a caller that holds this node
## without knowing its type identifies it: devtools_ext/commands.gd finds the panel by
## looking for a node answering all four of open/close/toggle/is_open, which is exactly the
## set that tells it apart from SkillTreeUi and LandPurchaseUi — both of those expose
## is_open() and toggle() and neither has open() or close(). Drop these two and that lookup
## silently starts matching the skill tree instead.
func open() -> void:
	set_open(true)


func close() -> void:
	set_open(false)


## The one place visibility changes. Kept as the public entry point because the
## InputManager signal, the toolbar and the tests all drive the panel through it; the
## frame only owns *how* it is drawn.
func set_open(open: bool) -> void:
	if _frame == null or _frame.is_open() == open:
		return

	if open:
		_frame.open()
	else:
		_frame.close()

	# Same handshake the inventory, crafting, skill and land panels use: stop the player
	# walking around behind the menu. Assigned rather than toggled, so a panel opened
	# twice cannot leave input disabled forever.
	if input_manager:
		input_manager.disable_input = open

	if not open:
		# A confirm must not survive the panel it was armed in — reopening to a live
		# "SURE?" would make the next tap a delete the player never asked for.
		_clear_pending_delete()


## Escape, the X and a tap on the backdrop all land here. The panel does not handle
## ui_cancel itself — PanelFrame does, and only while it is on screen, so two open
## panels cannot both answer one press.
func _on_close_requested() -> void:
	set_open(false)


func _on_opened() -> void:
	_set_status("", UiTheme.COLOR_TEXT_DIM)
	_refresh()


# --- accessors ---------------------------------------------------------------

## One row's action Button — `action` is "save", "load" or "delete" — or null.
##
## Public because the rows are generated, so `find_child("SaveButton")` returns
## whichever row sorted first rather than the one asked for. This is the handle the
## tests and the devtools bridge address a specific slot's button through.
func button_for(slot: int, action: String) -> Button:
	for row in _rows:
		if int(row["slot"]) == slot:
			return row.get(action) as Button
	return null


## How many slot rows are on screen. For tests and for a devtools status read.
func row_count() -> int:
	return _rows.size()


## The slot whose Delete is armed, or 0. Exposed so the two-step confirm can be
## asserted from outside rather than by reading a button's text.
func pending_delete_slot() -> int:
	return _pending_delete
