extends Control
class_name MobileControls

## Virtual touch controls for phone play (the itch.io web build): a virtual
## joystick on the left driving move_left / move_right / move_up / move_down, and
## a cluster of action buttons on the right driving gather's own InputMap actions.
##
## No gameplay lives here. Every button synthesises the *same* InputMap action the
## keyboard sends, with Input.parse_input_event(InputEventAction), so the existing
## InputManager -> Player -> HotBarInventory -> ResourceManager2 chain runs
## completely unchanged. parse_input_event is deliberate rather than
## Input.action_press: InputManager reads gather / attack / destroy from _input(),
## which only runs when an actual event is dispatched. Input.action_press updates
## the action state without dispatching anything, so the press would sit there
## unnoticed until some unrelated event happened to arrive.
##
## `gather` is a *hold*: press starts ResourceManager2's hold timer and release is
## what calls stop_removing_resource() (via Player._gather_input_release). So the
## gather button sends press on finger-down and release on finger-up. A one-shot
## tap would leave the mining timer running forever. The same is true of `destroy`.
##
## Buttons are hit-tested from _input() on InputEventScreenTouch rather than being
## real Button nodes, so a second finger works while the first one is holding the
## joystick — mouse emulation only ever tracks one touch index, so Button.pressed
## alone would silently drop those.
##
## Mounted in the UI2 CanvasLayer, never under Player/Camera2D/UI: that Control is
## world-space at 0.23 scale for the diegetic HUD (see CLAUDE.md).

## Emitted alongside every synthesised action, so a test can assert that a hold
## button really produced both halves without depending on frame timing.
signal action_sent(action: String, pressed: bool)

## Sentinel "action" for the hotbar cycle button. It is not an InputMap action —
## hot_bar_inventory.gd selects slots from _unhandled_key_input on KEY_1..KEY_6 and
## exposes no action — so it is handled separately in _press().
const HOTBAR_CYCLE := "@hotbar_cycle"

## hot_bar_inventory.gd matches `range(KEY_1, KEY_7)`, i.e. slots 1..6.
const HOTBAR_SLOT_COUNT := 6

## How often the overlay re-checks for a touchscreen. DisplayServer exposes no
## signal for it, and the self-test harness's `set-feature --touchscreen true`
## flips it mid-run, so it has to be polled — but once a second is imperceptible
## to a human and costs nothing next to a per-frame query that runs for the whole
## life of the game on every platform.
const TOUCH_POLL_INTERVAL := 1.0

## The addon joystick scene is authored at 300x300 with a 200px base centred in it.
## Both numbers are baked into its own layout, so the overlay scales the control
## rather than resizing it.
const JOYSTICK_SIZE := Vector2(300.0, 300.0)
const JOYSTICK_CLAMPZONE := 75.0
const JOYSTICK_DEADZONE := 10.0

## Button sizing, all derived from the viewport's shortest edge so the cluster is
## thumb-sized on a phone and not absurd on a desktop window. The reference edge
## that ratio is taken against is `UiTheme.REFERENCE_EDGE`; this file used to
## declare its own byte-identical 720.0, which is one more thing that could drift
## away from the panels. Nothing here may be a viewport *position* (see CLAUDE.md).
const BUTTON_BIG_FRACTION := 0.20
const BUTTON_BIG_MIN := 52.0
const BUTTON_BIG_MAX := 148.0
const BUTTON_SMALL_RATIO := 0.68
const BUTTON_PAD_RATIO := 0.16
const MARGIN_FRACTION := 0.035
const MARGIN_MIN := 10.0
const MARGIN_MAX := 40.0
const LABEL_SIZE_RATIO := 0.22
const LABEL_SIZE_MIN := 9
const JOYSTICK_SCALE_MIN := 0.45
const JOYSTICK_SCALE_MAX := 1.25

# Colours come from `UiTheme` — the overlay's own near-duplicate palette was the
# fourth copy of the same five values and the one that had already drifted (its
# background was a shade more transparent than the panels'). `overlay_style()` is
# the variant meant for chrome sitting directly over the world with no backdrop,
# which is exactly what these buttons and the hotbar are.

## The button cluster, laid out in rows measured from a screen corner. Rows count
## away from the corner, and within a row buttons are placed right-to-left in the
## order this table declares them. Adding a button is a one-line edit here: _layout
## derives the set of (corner, row) groups from the table itself.
##
## Which of gather's actions earn a button, and why:
##   gather    the whole game — mine a node, and (through HotBarInventory) place
##             the held building. Held.
##   attack    the only way to fight the enemy waves.
##   action    open a chest / crafting station; without it the crafting half of the
##             game is unreachable on a phone.
##   destroy   removes a misplaced building. Held, same as gather.
##   ITEM      cycles the hotbar selection forward. Not an action at all. The
##             hotbar now carries its own < and > buttons and its slots are
##             tappable, so this is no longer the only way to change slots — but
##             it is the one that stays under the thumb already holding the right
##             cluster, and one-handed portrait play is the case that made the
##             overlay worth building. The hotbar's arrows are the *discoverable*
##             affordance; this is the fast one. Both go through the same
##             HotBarInventory.select_slot().
##   inventory / skills / land   the three panels. They are the progression UI, and
##             on a phone this cluster is the only way *into* them. It used to be
##             the only way back out too, which is why the overlay was mounted on
##             top of everything; every panel now closes from its own PanelFrame X,
##             a tap on the backdrop, or Escape, so that constraint is gone and the
##             overlay sits *beneath* the panels instead. handle_touch_event()
##             declines presses while one is open so the two cannot both answer the
##             same tap.
##
## Left off deliberately: `save` and `load` (debug bindings, and there are already
## Save/Load buttons in the camera HUD) and the mouse buttons (touch already
## emulates a left click).
const BUTTON_SPECS := [
	{"name": "GatherButton", "action": "gather", "label": "MINE", "big": true, "primary": true, "corner": "br", "row": 0},
	{"name": "AttackButton", "action": "attack", "label": "HIT", "big": true, "primary": false, "corner": "br", "row": 0},
	{"name": "ActionButton", "action": "action", "label": "USE", "big": false, "primary": false, "corner": "br", "row": 1},
	{"name": "DestroyButton", "action": "destroy", "label": "BREAK", "big": false, "primary": false, "corner": "br", "row": 1},
	{"name": "HotbarButton", "action": HOTBAR_CYCLE, "label": "ITEM", "big": false, "primary": false, "corner": "br", "row": 1},
	{"name": "SkillsButton", "action": "skills", "label": "SKILL", "big": false, "primary": false, "corner": "tr", "row": 0},
	{"name": "InventoryButton", "action": "inventory", "label": "BAG", "big": false, "primary": false, "corner": "tr", "row": 0},
	{"name": "LandButton", "action": "land", "label": "LAND", "big": false, "primary": false, "corner": "tr", "row": 0},
]

## The corners the layout walks, in the order rows stack away from each.
const CORNERS := ["br", "tr"]

## The buttons that open a panel rather than acting on the world. They stay live
## while `disable_input` is raised for death and respawn, matching the keyboard
## bindings in input_manager.gd. See _press_blocked_for().
const MENU_ACTIONS := ["inventory", "skills", "land"]

var _joystick: Control

## The generated button Controls, in BUTTON_SPECS order, and their metadata.
var _buttons: Array[Control] = []
var _button_action: Dictionary = {}

## touch index -> the button that finger is currently holding.
var _held: Dictionary = {}

## The project's InputManager, resolved by relative path because main.tscn's root
## belongs to every group and get_first_node_in_group() therefore returns the root
## (see CLAUDE.md). Null in a test that instantiates this scene on its own, which
## reads as "no panel is open" — the right answer there.
var _input_manager: InputManager

## Last value read from DisplayServer, so _process only reacts to changes.
var _touch_available := false
var _force_visible := false


func _ready() -> void:
	add_to_group("UI")

	# The overlay must never swallow a click aimed at the world; every hit test it
	# does is manual, from _input().
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)

	_joystick = get_node_or_null("VirtualJoystick") as Control
	if _joystick == null:
		push_error("MobileControls: no VirtualJoystick child; movement will have no touch input")

	# UI2/MobileControls -> Main/InputManager. The same relative hop the rest of the
	# UI2 nodes make.
	_input_manager = get_node_or_null("../../InputManager") as InputManager

	_build_buttons()
	_layout()

	var vp := get_viewport()
	if vp != null and not vp.size_changed.is_connected(_layout):
		vp.size_changed.connect(_layout)

	_touch_available = DisplayServer.is_touchscreen_available()
	_apply_visibility()

	# DisplayServer.is_touchscreen_available() is a query, not a signal, so the only
	# way to notice `set-feature --touchscreen true` (which drives
	# Input.set_emulate_touch_from_mouse) is to ask again. Reading it once here would
	# mean the overlay never appears for a desktop test run.
	var poll := Timer.new()
	poll.name = "TouchPoll"
	poll.wait_time = TOUCH_POLL_INTERVAL
	poll.timeout.connect(_poll_touch_available)
	add_child(poll)
	poll.start()


func _poll_touch_available() -> void:
	var now := DisplayServer.is_touchscreen_available()
	if now != _touch_available:
		_touch_available = now
		_apply_visibility()


## Shows the overlay regardless of whether a touchscreen is reported. For tests and
## for eyeballing the layout on desktop.
func set_forced_visible(on: bool) -> void:
	_force_visible = on
	_apply_visibility()


## The generated Control for an InputMap action (or HOTBAR_CYCLE), or null.
func get_button_for(action: String) -> Control:
	for i in mini(BUTTON_SPECS.size(), _buttons.size()):
		if str(BUTTON_SPECS[i]["action"]) == action:
			return _buttons[i]
	return null


## Every action this overlay can send, HOTBAR_CYCLE included.
func get_actions() -> Array[String]:
	var out: Array[String] = []
	for spec in BUTTON_SPECS:
		out.append(str(spec["action"]))
	return out


func _apply_visibility() -> void:
	var want := _force_visible or _touch_available

	# On desktop the overlay is hidden for the entire session. Without this, every
	# mouse-motion event in the game would still make the trip into _input() just to
	# be turned away by the `not visible` guard.
	set_process_input(want)

	if want == visible:
		return

	visible = want
	if not want:
		_release_all()


func _input(event: InputEvent) -> void:
	if handle_touch_event(event):
		get_viewport().set_input_as_handled()


## The whole touch routing, split out from _input() so it can be driven directly
## without a live viewport. Returns true when the event was consumed.
##
## Presses are declined while a modal panel is open; releases never are. See
## `_presses_blocked()` for why the two halves are not treated alike.
func handle_touch_event(event: InputEvent) -> bool:
	if not visible:
		return false

	var blocked := _presses_blocked()

	var touch := event as InputEventScreenTouch
	if touch != null:
		if touch.pressed:
			var button := _button_at(touch.position)
			if button != null and not _press_blocked_for(button, blocked):
				_press(touch.index, button)
				return true
		elif _held.has(touch.index):
			_release(touch.index)
			return true
		return false

	var drag := event as InputEventScreenDrag
	if drag != null and _held.has(drag.index):
		# Sliding off a button releases it; sliding onto another takes that one over.
		var over := _button_at(drag.position)
		if over != _held[drag.index]:
			_release(drag.index)
			# ...unless a panel opened mid-drag, in which case letting go is all that
			# is left to do.
			if over != null and not _press_blocked_for(over, blocked):
				_press(drag.index, over)
			return true

	return false


## True while a modal panel owns the screen.
##
## The overlay hit-tests its own rects from `_input()`, which runs before the
## viewport picks a Control, and marks the event handled. So a touch on the BAG /
## SKILL / LAND cluster used to fire its action even with a panel painted over the
## top of it: the player tapped what looked like the panel and something else
## happened underneath. Declining the event (rather than consuming it) lets it fall
## through to the panel's own GUI handling, which is what a tap there should hit.
##
## `InputManager.disable_input` is the signal because every panel already sets it
## true on open and false on close through its `set_open()` handshake — there is no
## second source of truth to keep in step.
##
## **Presses only.** A release for a finger already in `_held` is always processed,
## even mid-panel. `gather` and `destroy` are holds: press starts
## ResourceManager2's timer and the release is what calls
## stop_removing_resource(). Swallow that release — because a panel opened under
## the other thumb — and the action latches down forever with the tile stuck on its
## animated mid-gather frame. That is gather-3zg, and it is why input_manager.gd's
## own releases are ungated too.
func _presses_blocked() -> bool:
	if _input_manager == null:
		return false
	return bool(_input_manager.disable_input)


## Whether this particular button declines the press, given the blanket
## `_presses_blocked()` verdict.
##
## `disable_input` alone is very slightly too broad: `player.gd:respawn()` also
## raises it for the half-second death-and-respawn window, and input_manager.gd is
## explicit that the three menu toggles must *not* be gated on it — "opening a menu
## while dead or mid-respawn is harmless, and being locked out of it is not". A flat
## gate would have locked a phone player out of their own inventory every time they
## died, which is precisely the complaint the keyboard build already fixed.
##
## So the two reasons to decline are separated:
##   * a panel is genuinely on screen — decline everything, the cluster is buried
##     under it and the panel carries its own close button now;
##   * input is merely disabled (dead, mid-respawn) — decline the gameplay actions
##     but let the menu buttons through, matching the keyboard.
func _press_blocked_for(button: Control, blocked: bool) -> bool:
	if _modal_panel_open():
		return true
	if not blocked:
		return false
	return not MENU_ACTIONS.has(str(_button_action.get(button, "")))


## Whether a PanelFrame is currently on screen anywhere in this CanvasLayer.
##
## Asks the frames themselves rather than trusting `disable_input`, because that
## flag answers "can the player act", not "is something covering the buttons", and
## only the second question is the one draw order cannot settle.
func _modal_panel_open() -> bool:
	var parent := get_parent()
	if parent == null:
		return false

	for sibling in parent.get_children():
		if sibling == self:
			continue
		# owned = false: every panel builds its PanelFrame in code, so none of them
		# are owned by a scene and an owned-only search finds nothing.
		for frame in sibling.find_children("*", "PanelFrame", true, false):
			if frame.visible:
				return true
	return false


func _notification(what: int) -> void:
	# Losing focus (app backgrounded, browser tab switched) drops the matching touch
	# release, which would leave `gather` latched down and the mining timer running.
	if what == NOTIFICATION_APPLICATION_FOCUS_OUT or what == NOTIFICATION_WM_WINDOW_FOCUS_OUT:
		_release_all()


func _button_at(point: Vector2) -> Control:
	for button in _buttons:
		if button.visible and button.get_global_rect().has_point(point):
			return button
	return null


func _press(index: int, button: Control) -> void:
	# A dropped touch-up (a browser gesture, an itch.io iframe scroll, a touch that began
	# while the overlay was hidden) leaves the old binding in _held. The browser then
	# reuses that identifier for the next finger, and without this the old button's action
	# — `gather`, typically — would be overwritten and never released.
	if _held.has(index):
		_release(index)

	_held[index] = button
	_set_pressed_look(button, true)
	send_action(_button_action.get(button, ""), true)


func _release(index: int) -> void:
	var button: Control = _held[index]
	_held.erase(index)

	# A second finger may still be on the same button.
	if _held.values().has(button):
		return

	_set_pressed_look(button, false)
	send_action(_button_action.get(button, ""), false)


func _release_all() -> void:
	# keys() is a fresh array, so erasing inside the loop is safe.
	for index in _held.keys():
		_release(index)

	# The joystick keeps its own _touch_index and its own latched move_* actions, and
	# nothing here ever touched them: after a tab switch with a thumb on the stick the
	# player kept walking, and — worse — the stale index made the joystick swallow the
	# touch-up of whichever finger next held it, which latches `gather` down for good
	# (see the guard in virtual_joystick.gd:_input).
	if _joystick != null and _joystick.has_method("reset"):
		_joystick.reset()


func _set_pressed_look(button: Control, down: bool) -> void:
	button.modulate = UiTheme.PRESSED_MODULATE if down else Color.WHITE


## Feeds one half of an action into the engine, exactly as the keyboard would. The
## single place that knows what a button's `action` means, so HOTBAR_CYCLE and any
## future non-InputMap button cost one branch here rather than one in each of
## _press() and _release(). Public because the gather/destroy holds are the part
## most worth driving from a test or a devtools verb.
func send_action(action: String, pressed: bool) -> void:
	if action == "":
		return

	if action == HOTBAR_CYCLE:
		# A one-shot: the slot changes on finger-down and there is nothing to hold.
		if pressed:
			_cycle_hotbar()
	elif InputMap.has_action(action):
		var event := InputEventAction.new()
		event.action = action
		event.pressed = pressed
		Input.parse_input_event(event)
	else:
		push_error("MobileControls: no InputMap action named '%s'" % action)
		return

	action_sent.emit(action, pressed)


## Advances the hotbar selection by one slot. hot_bar_inventory.gd selects from
## _unhandled_key_input on KEY_1..KEY_6 and publishes no InputMap action, so
## sending the same key it already listens for is the only way to drive it without
## copying its selection logic in here. The current slot is read back off the
## hotbar rather than tracked locally, so number keys and this button stay in sync.
##
## The hotbar has since grown a public `step_selection()` that this could call
## directly, and every one of its own affordances goes through it. The key is kept
## anyway: it is the one path that does not care where the hotbar is mounted or
## whether this overlay can find it, and it now lands in exactly the same
## `select_slot()` as the arrows and the taps, so there is nothing left to drift.
func _cycle_hotbar() -> void:
	var current := 0
	var hotbar := _find_hotbar()
	if hotbar != null:
		var idx: Variant = hotbar.get("selected_index")
		if typeof(idx) == TYPE_INT:
			current = idx

	var next: int = posmod(current + 1, HOTBAR_SLOT_COUNT)

	# Both halves: nothing binds KEY_1..KEY_6, but leaving a key logically down is
	# still a trap.
	for pressed in [true, false]:
		var event := InputEventKey.new()
		event.keycode = KEY_1 + next
		event.physical_keycode = event.keycode
		event.pressed = pressed
		Input.parse_input_event(event)


func _find_hotbar() -> Node:
	var parent := get_parent()
	if parent == null:
		return null
	return parent.get_node_or_null("HotBarInventory")


func _build_buttons() -> void:
	for spec in BUTTON_SPECS:
		var button := Control.new()
		button.name = str(spec["name"])
		button.mouse_filter = Control.MOUSE_FILTER_IGNORE

		var background := Panel.new()
		background.name = "Background"
		background.mouse_filter = Control.MOUSE_FILTER_IGNORE
		background.add_theme_stylebox_override("panel", _button_style(spec["primary"] == true))
		button.add_child(background)
		background.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)

		var label := Label.new()
		label.name = "Label"
		label.text = str(spec["label"])
		label.mouse_filter = Control.MOUSE_FILTER_IGNORE
		label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
		label.add_theme_color_override("font_color", UiTheme.COLOR_TEXT)
		button.add_child(label)
		label.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)

		add_child(button)
		_buttons.append(button)
		_button_action[button] = str(spec["action"])


## `primary` maps onto UiTheme's `accent`: the gold, one-pixel-thicker border the
## hotbar's selected slot also wears, so "this is the important one" reads the
## same everywhere.
func _button_style(primary: bool) -> StyleBoxFlat:
	return UiTheme.overlay_style(primary)


## The four lengths the whole layout is built out of, in one place so that
## `_layout()` and anything asking how much screen the overlay covers cannot
## derive them differently. `small` takes UiTheme's touch floor: at the bottom of
## the range a secondary button worked out to 35px, well under the 48px
## accessibility minimum the rest of the UI now clears.
func _metrics(vp: Vector2) -> Dictionary:
	var shortest := minf(vp.x, vp.y)
	var big := clampf(shortest * BUTTON_BIG_FRACTION, BUTTON_BIG_MIN, BUTTON_BIG_MAX)
	return {
		"big": big,
		"small": maxf(big * BUTTON_SMALL_RATIO, UiTheme.TOUCH_MIN),
		"pad": big * BUTTON_PAD_RATIO,
		"margin": clampf(shortest * MARGIN_FRACTION, MARGIN_MIN, MARGIN_MAX),
	}


func _joystick_scale(vp: Vector2) -> float:
	return clampf(
		minf(vp.x, vp.y) / UiTheme.REFERENCE_EDGE, JOYSTICK_SCALE_MIN, JOYSTICK_SCALE_MAX)


## How many pixels up from the bottom edge this overlay is occupying, so other
## bottom-anchored UI can sit clear of it. On a portrait phone the joystick and
## the thumb cluster own both bottom corners and the hotbar is very nearly
## screen-wide, so there is no bottom-centre gap for it to slip into — without
## this the hotbar renders underneath MINE and HIT and a tap hits both.
##
## Zero while the overlay is hidden, which is the whole desktop session.
func get_bottom_obstruction_height() -> float:
	if not visible:
		return 0.0

	var vp := get_viewport_rect().size
	if vp.x <= 0.0 or vp.y <= 0.0:
		return 0.0

	var metrics := _metrics(vp)
	var big: float = metrics["big"]
	var small: float = metrics["small"]
	var pad: float = metrics["pad"]
	var margin: float = metrics["margin"]

	# Same walk `_layout()` makes over the bottom-right corner, so a row added to
	# BUTTON_SPECS raises this by itself.
	var cluster := margin
	for indices in _rows_for("br"):
		cluster += _row_height(indices, big, small) + pad

	var joystick := 0.0
	if _joystick != null:
		joystick = margin + JOYSTICK_SIZE.y * _joystick_scale(vp)

	return maxf(cluster, joystick)


## Sizes and positions everything from the current viewport, because the project
## runs with window/stretch/mode="disabled": the viewport is the device's real
## pixel size, so a phone gets a viewport a fraction of the desktop one's and any
## fixed pixel layout would come out unusable at one end or the other.
func _layout() -> void:
	var vp := get_viewport_rect().size
	if vp.x <= 0.0 or vp.y <= 0.0:
		return

	var metrics := _metrics(vp)
	var big: float = metrics["big"]
	var small: float = metrics["small"]
	var pad: float = metrics["pad"]
	var margin: float = metrics["margin"]

	# Rows stack away from their corner, each one inset by the ones before it. The
	# groups come from BUTTON_SPECS, so a new row appears on screen the moment it is
	# added to the table — the previous form listed the three groups here by hand and
	# a fourth would have been built, hit-tested and left sitting at (0, 0).
	for corner in CORNERS:
		var inset := margin
		for indices in _rows_for(corner):
			var height := _row_height(indices, big, small)
			var top := (vp.y - inset - height) if corner == "br" else inset
			_layout_row(indices, vp.x, top, height, big, small, pad, margin)
			inset += height + pad

	if _joystick != null:
		var scale_factor := _joystick_scale(vp)
		_joystick.set_anchors_preset(Control.PRESET_TOP_LEFT)
		_joystick.size = JOYSTICK_SIZE
		_joystick.scale = Vector2(scale_factor, scale_factor)
		_joystick.position = Vector2(margin, vp.y - margin - JOYSTICK_SIZE.y * scale_factor)
		# Both zones are compared against a screen-space vector inside the addon, so
		# they have to be scaled alongside the control or the tip stops where the art
		# does not.
		_joystick.set("clampzone_size", JOYSTICK_CLAMPZONE * scale_factor)
		_joystick.set("deadzone_size", JOYSTICK_DEADZONE * scale_factor)


## BUTTON_SPECS indices for one corner, grouped into rows and ordered by row number.
func _rows_for(corner: String) -> Array:
	var rows := {}
	for i in BUTTON_SPECS.size():
		var spec: Dictionary = BUTTON_SPECS[i]
		if str(spec["corner"]) != corner:
			continue
		var row := int(spec["row"])
		if not rows.has(row):
			rows[row] = []
		rows[row].append(i)

	var numbers := rows.keys()
	numbers.sort()

	var out := []
	for number in numbers:
		out.append(rows[number])
	return out


## A row is as tall as its tallest button, so a row of small buttons does not
## reserve the height of a big one.
func _row_height(indices: Array, big: float, small: float) -> float:
	var height := 0.0
	for i in indices:
		height = maxf(height, big if BUTTON_SPECS[i]["big"] == true else small)
	return height


## Lays one row out from the right edge, walking leftwards in table order.
func _layout_row(indices: Array, view_width: float, top: float, row_height: float,
		big: float, small: float, pad: float, margin: float) -> void:
	var right := view_width - margin
	for i in indices:
		# _build_buttons appends in BUTTON_SPECS order, so the index is the button.
		var button := _buttons[i]
		var side := big if BUTTON_SPECS[i]["big"] == true else small
		right -= side
		button.position = Vector2(right, top + (row_height - side) * 0.5)
		button.size = Vector2(side, side)
		right -= pad

		var label := button.get_node_or_null("Label") as Label
		if label != null:
			label.add_theme_font_size_override(
				"font_size", maxi(LABEL_SIZE_MIN, int(side * LABEL_SIZE_RATIO)))
