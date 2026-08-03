extends RefCounted

## Guards for the save-slot panel.
##
## Three of these are about a rendering the player only ever sees on the day something
## has gone wrong, which is exactly when nobody is running the game to check it: an
## empty slot, and a slot whose file is present but whose header will not parse. The
## panel has to tell those two apart — an empty slot is offered Save, a damaged one is
## offered Save *and* Delete but never Load, because Load is the action that would fail
## on it — and neither state is reachable by playing the game normally.
##
## They run against a stub rather than the real SaveLoad, deliberately. A test that
## drove the real one would have to write files into user:// to reach the populated
## case, could not reach the damaged case at all without corrupting one by hand, and
## would fail for reasons that have nothing to do with this panel every time the save
## format changed. The stub is the whole slot API in twenty lines, and it is what makes
## "an empty slot does not offer Load" an assertion instead of a screenshot.
##
## The layout test is the gather-6fx class of bug: a panel tuned against a desktop
## window that overflows the moment the viewport is a phone's. This one is worse than
## most, because the panel is here *for* the phone — `[` and `]` are the only other way
## to save, and a phone has neither key.

var _T  # assertion helper injected by run_tests.gd

## A portrait phone. The panel must be usable here or it has failed at its purpose.
const PHONE := Vector2i(390, 844)

## Stands in for SaveLoad. Implements exactly the slot API the panel is allowed to call
## and records what it was asked to do, so "Delete takes two presses" is a count rather
## than an impression.
##
## A Node rather than a RefCounted only because the panel holds its save system as a
## scene node in the real game; nothing here needs the tree.
##
## Declared above the field that is typed with it: an inner class referenced before it
## is declared has been an unreliable forward reference in GDScript, and a test script
## that fails to parse is reported as a runner error rather than as a failure.
class SlotStub extends Node:
	var slots: Array = []
	var current_slot: int = 0

	## Every call the panel made, in order, so a test can assert both that an action
	## happened and that it did not happen twice.
	var saved: Array[int] = []
	var loaded: Array[int] = []
	var deleted: Array[int] = []

	## Flip these to exercise the failure branches without inventing a broken disk.
	var save_result := true
	var load_result := true
	var delete_result := true

	func list_slots() -> Array:
		return slots

	func slot_info(slot: int) -> Dictionary:
		for entry in slots:
			if int(entry.get("slot", 0)) == slot:
				return entry
		return {}

	func save_to_slot(slot: int) -> bool:
		saved.append(slot)
		return save_result

	func load_from_slot(slot: int) -> bool:
		loaded.append(slot)
		return load_result

	func delete_slot(slot: int) -> bool:
		deleted.append(slot)
		return delete_result


var _stub: SlotStub
var _panel: SaveSlotUi
var _hosted: Node


func setup() -> void:
	_stub = SlotStub.new()
	# The three states the panel has to draw differently, one per slot: a good save, an
	# empty slot, and a file whose header will not parse.
	_stub.slots = [
		_info(1, true, true, 7, 12, 1_754_200_000),
		_info(2, false, false, 0, 0, 0),
		_info(3, true, false, 0, 0, 0),
	]
	_stub.current_slot = 1


func teardown() -> void:
	if _hosted != null:
		_T.free_ui(_hosted)
		_hosted = null
		_panel = null
	if _stub != null and is_instance_valid(_stub):
		# Never parented — the panel only holds a reference — so nothing else frees it.
		_stub.free()
		_stub = null


## A row's metadata line, or null if that row was never drawn. The rows are generated,
## so this walks from the named box rather than calling find_child("Detail") on the
## panel, which would return whichever row sorted first.
func _detail(slot: int) -> Label:
	var box := _panel.find_child("Slot_%d" % slot, true, false)
	if box == null:
		return null
	return box.find_child("Detail", true, false) as Label


## One slot_info dictionary. Always carries every key, which is the contract the panel
## is written against: it branches on the *values*, never on whether a key is present.
func _info(slot: int, exists: bool, readable: bool, level: int, radius: int, saved_at: int) -> Dictionary:
	return {
		"slot": slot,
		"exists": exists,
		"readable": readable,
		"version": 1,
		"saved_at": saved_at,
		"level": level,
		"land_radius": radius,
	}


## Builds the panel against the stub, hosts it in a real sized viewport and opens it.
##
## Opened before anything is measured, on purpose: Godot does not sort containers
## underneath a hidden Control, so a closed panel keeps whatever rect it was constructed
## with and every geometry assertion reads a stale number rather than a laid-out one.
## Returns "" or the reason it could not be built.
func _open(viewport_size: Vector2i = Vector2i(1152, 648)) -> String:
	_panel = SaveSlotUi.new()
	_panel.name = "SaveSlotUi"
	# Injected before the node enters the tree, so _bind_systems() finds it already set
	# and never goes looking for the real save system.
	_panel.save_load = _stub

	# There is no .tscn — the panel builds itself in code, so instantiate_ui takes the
	# node. Without it headless pumps no frames and every size stays (0, 0).
	_hosted = await _T.instantiate_ui(_panel, viewport_size)
	if _hosted == null:
		return "instantiate_ui returned null"

	_panel.set_open(true)
	await _panel.get_tree().process_frame
	await _panel.get_tree().process_frame
	return ""


# --- what the rows say -------------------------------------------------------

func test_there_is_one_row_per_slot() -> String:
	var err: String = await _open()
	if err != "":
		return err

	var a: String = _T.assert_eq(_panel.row_count(), _stub.slots.size(),
		"the panel should draw one row per entry list_slots() returns")
	if a != "":
		return a

	# Named rather than generated: the devtools bridge and these tests both address a
	# slot by node path, and a @PanelContainer@nn shifts with the node count.
	for slot: int in [1, 2, 3]:
		var box := _panel.find_child("Slot_%d" % slot, true, false)
		var b: String = _T.assert_true(box != null, "there should be a Slot_%d row" % slot)
		if b != "":
			return b

	return ""


func test_a_populated_slot_shows_its_level_radius_and_date() -> String:
	var err: String = await _open()
	if err != "":
		return err

	var detail := _detail(1)
	if detail == null:
		return "slot 1 has no Detail label"

	var a: String = _T.assert_true(detail.text.contains("Level 7"),
		"a populated slot should show its level, got '%s'" % detail.text)
	if a != "":
		return a

	# "radius 12" rather than "12": the formatted date is full of digits, so a bare
	# substring check would pass on a row that never printed the radius at all.
	var b: String = _T.assert_true(detail.text.contains("radius 12"),
		"a populated slot should show its land radius, got '%s'" % detail.text)
	if b != "":
		return b

	# The date is formatted, not printed as a unix stamp. "1754200000" on a save row is
	# the readout this panel exists to replace.
	return _T.assert_false(detail.text.contains("1754200000"),
		"saved_at should be formatted as a date, got '%s'" % detail.text)


func test_an_empty_slot_offers_save_but_not_load() -> String:
	# Slot 2 is empty. Load is the one action that cannot mean anything on it, and a
	# Load that silently did nothing would read as a broken save system rather than as
	# an empty slot.
	var err: String = await _open()
	if err != "":
		return err

	var save_button := _panel.button_for(2, "save")
	var load_button := _panel.button_for(2, "load")
	if save_button == null or load_button == null:
		return "slot 2 is missing its action buttons"

	var a: String = _T.assert_false(save_button.disabled, "an empty slot should still offer Save")
	if a != "":
		return a

	var b: String = _T.assert_true(load_button.disabled, "an empty slot must not offer Load")
	if b != "":
		return b

	var detail := _detail(2)
	return _T.assert_true(detail != null and detail.text.contains("Empty"),
		"an empty slot should say so, got '%s'" % ("<none>" if detail == null else detail.text))


func test_a_damaged_slot_offers_save_and_delete_but_never_load() -> String:
	# Slot 3 is `exists: true, readable: false` — the file is there and its header will
	# not parse. Overwriting it and discarding it are the only two things a player can
	# usefully do; Load is the one that would fail. This is also the case that proves
	# the panel branches on the *value* of `readable` rather than on `exists` alone.
	var err: String = await _open()
	if err != "":
		return err

	var save_button := _panel.button_for(3, "save")
	var load_button := _panel.button_for(3, "load")
	var delete_button := _panel.button_for(3, "delete")
	if save_button == null or load_button == null or delete_button == null:
		return "slot 3 is missing its action buttons"

	var a: String = _T.assert_false(save_button.disabled, "a damaged slot should offer Save to overwrite it")
	if a != "":
		return a

	var b: String = _T.assert_false(delete_button.disabled, "a damaged slot should offer Delete")
	if b != "":
		return b

	return _T.assert_true(load_button.disabled, "a damaged slot must never offer Load")


# --- actions -----------------------------------------------------------------

func test_save_and_load_call_the_slot_api_for_that_row() -> String:
	# Each row's buttons are bound to their own slot number. Bound wrongly, every row
	# would drive slot 1 and the panel would look completely correct while destroying
	# the wrong save.
	var err: String = await _open()
	if err != "":
		return err

	var save_button := _panel.button_for(2, "save")
	var load_button := _panel.button_for(1, "load")
	if save_button == null or load_button == null:
		return "the panel is missing the buttons under test"

	save_button.pressed.emit()
	var a: String = _T.assert_eq(_stub.saved.size(), 1, "Save should call save_to_slot once")
	if a != "":
		return a
	var b: String = _T.assert_eq(_stub.saved[0], 2,
		"pressing Save on row 2 should call save_to_slot(2), not another row's")
	if b != "":
		return b

	load_button.pressed.emit()
	var c: String = _T.assert_eq(_stub.loaded.size(), 1, "Load should call load_from_slot once")
	if c != "":
		return c
	return _T.assert_eq(_stub.loaded[0], 1,
		"pressing Load on row 1 should call load_from_slot(1)")


func test_deleting_takes_two_presses() -> String:
	# The confirm exists because Delete is irreversible and, on a phone, sits a
	# fingertip from Load. One press must arm it and nothing more.
	var err: String = await _open()
	if err != "":
		return err

	var delete_button := _panel.button_for(1, "delete")
	if delete_button == null:
		return "slot 1 has no Delete button"

	delete_button.pressed.emit()

	var a: String = _T.assert_eq(_stub.deleted.size(), 0,
		"the first press must not delete anything")
	if a != "":
		return a

	var b: String = _T.assert_eq(_panel.pending_delete_slot(), 1,
		"the first press should arm slot 1")
	if b != "":
		return b

	# The button has to *say* it is armed, or the second press is a surprise.
	var c: String = _T.assert_eq(delete_button.text, SaveSlotUi.DELETE_CONFIRM_LABEL,
		"an armed Delete should ask for confirmation")
	if c != "":
		return c

	delete_button.pressed.emit()

	var d: String = _T.assert_eq(_stub.deleted.size(), 1,
		"the second press should call delete_slot exactly once")
	if d != "":
		return d

	var e: String = _T.assert_eq(_stub.deleted[0], 1, "it should have deleted slot 1")
	if e != "":
		return e

	return _T.assert_eq(_panel.pending_delete_slot(), 0,
		"the confirm should disarm once it has been acted on")


func test_any_other_interaction_disarms_a_pending_delete() -> String:
	# A button left saying "SURE?" while the player does something else is a trap the
	# next tap springs — and on a phone the next tap is often exactly there.
	var err: String = await _open()
	if err != "":
		return err

	var delete_button := _panel.button_for(1, "delete")
	var save_button := _panel.button_for(2, "save")
	if delete_button == null or save_button == null:
		return "the panel is missing the buttons under test"

	delete_button.pressed.emit()
	save_button.pressed.emit()

	var a: String = _T.assert_eq(_panel.pending_delete_slot(), 0,
		"pressing another button should disarm the pending delete")
	if a != "":
		return a

	var b: String = _T.assert_eq(delete_button.text, SaveSlotUi.DELETE_LABEL,
		"a disarmed Delete should go back to its ordinary face")
	if b != "":
		return b

	return _T.assert_eq(_stub.deleted.size(), 0, "nothing should have been deleted")


func test_closing_the_panel_disarms_a_pending_delete() -> String:
	# Reopening to a live "SURE?" would make the first tap of the next session a
	# deletion the player never asked for.
	var err: String = await _open()
	if err != "":
		return err

	var delete_button := _panel.button_for(1, "delete")
	if delete_button == null:
		return "slot 1 has no Delete button"

	delete_button.pressed.emit()
	_panel.set_open(false)

	return _T.assert_eq(_panel.pending_delete_slot(), 0,
		"closing the panel should disarm the pending delete")


# --- formatting --------------------------------------------------------------

func test_saved_at_is_rendered_as_a_date_not_a_number() -> String:
	# 0 means "the header did not say", which is a legitimate answer for a save written
	# before the field existed — it must not render as 1970.
	var unknown := SaveSlotUi.format_saved_at(0)
	var a: String = _T.assert_false(unknown.contains("1970"),
		"an unknown saved_at should not be drawn as the epoch, got '%s'" % unknown)
	if a != "":
		return a

	# YYYY-MM-DD HH:MM. Asserting the shape rather than the value: the panel converts to
	# the player's own timezone, so the exact hour depends on the machine running this.
	var stamp := SaveSlotUi.format_saved_at(1_754_200_000)
	var b: String = _T.assert_eq(stamp.length(), 16,
		"a formatted date should be 'YYYY-MM-DD HH:MM', got '%s'" % stamp)
	if b != "":
		return b

	return _T.assert_true(stamp.begins_with("2025") or stamp.begins_with("2026"),
		"a 2025 timestamp should render in the year it happened, got '%s'" % stamp)


# --- layout ------------------------------------------------------------------

func test_the_panel_fits_a_portrait_phone_without_overflowing() -> String:
	# The gather-6fx failure: a panel sized against a desktop window that hangs off both
	# edges of a phone. Every size in this file goes through UiTheme.scaled*, and this
	# is what says so.
	var err: String = await _open(PHONE)
	if err != "":
		return err

	var frame := _panel.find_child("Frame", true, false) as PanelContainer
	if frame == null:
		return "the panel has no inner Frame PanelContainer"

	var rect := frame.get_global_rect()
	var view := Vector2(PHONE)

	var a: String = _T.assert_gte(rect.position.x, 0.0, "the panel should not overflow the left edge")
	if a != "":
		return a

	var b: String = _T.assert_gte(view.x - rect.end.x, 0.0,
		"the panel should not overflow the right edge (ends at %s of %s)" % [rect.end.x, view.x])
	if b != "":
		return b

	return _T.assert_gte(view.y - rect.end.y, 0.0,
		"the panel should not overflow the bottom edge (ends at %s of %s)" % [rect.end.y, view.y])


func test_every_action_button_is_reachable_and_thumb_sized_on_a_phone() -> String:
	# Two failures in one: a button smaller than the touch floor, and a row wider than
	# the frame — the second one pushes Delete off the right-hand edge into the
	# ScrollContainer's horizontal overflow, where a player would never find it.
	var err: String = await _open(PHONE)
	if err != "":
		return err

	var frame := _panel.find_child("Frame", true, false) as PanelContainer
	if frame == null:
		return "the panel has no inner Frame PanelContainer"
	var bounds := frame.get_global_rect()

	for slot: int in [1, 2, 3]:
		for action: String in ["save", "load", "delete"]:
			var button := _panel.button_for(slot, action)
			if button == null:
				return "slot %d has no %s button" % [slot, action]

			var rect := button.get_global_rect()

			var a: String = _T.assert_gte(rect.size.y, UiTheme.TOUCH_MIN,
				"slot %d's %s button should clear the touch floor, got %s" % [slot, action, rect.size.y])
			if a != "":
				return a

			var b: String = _T.assert_gte(bounds.end.x - rect.end.x, -0.5,
				"slot %d's %s button should sit inside the panel, ending at %s of %s" % [
					slot, action, rect.end.x, bounds.end.x])
			if b != "":
				return b

	return ""


func test_the_panel_survives_a_save_system_that_is_not_there() -> String:
	# main.tscn declares UI before Systems, so this panel is readied while SaveLoad is
	# not yet available — and an exported build with a missing save system should show
	# an inert panel, not take the whole UI CanvasLayer down with it.
	_panel = SaveSlotUi.new()
	_panel.name = "SaveSlotUi"
	_hosted = await _T.instantiate_ui(_panel, Vector2i(1152, 648))
	if _hosted == null:
		return "instantiate_ui returned null"

	_panel.set_open(true)
	await _panel.get_tree().process_frame

	return _T.assert_eq(_panel.row_count(), 0,
		"with no save system the panel should draw no rows rather than crash")
