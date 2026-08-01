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

## The addon joystick scene is authored at 300x300 with a 200px base centred in it.
## Both numbers are baked into its own layout, so the overlay scales the control
## rather than resizing it.
const JOYSTICK_SIZE := Vector2(300.0, 300.0)
const JOYSTICK_CLAMPZONE := 75.0
const JOYSTICK_DEADZONE := 10.0

const COLOR_BG := Color(0.086, 0.102, 0.129, 0.66)
const COLOR_BORDER := Color(0.49, 0.52, 0.58, 0.55)
const COLOR_BORDER_PRIMARY := Color("ffd166")
const COLOR_LABEL := Color("f2f4f8")
const PRESSED_MODULATE := Color(0.62, 0.72, 0.85, 1.0)

## The button cluster, laid out in rows measured from a screen corner. `col` 0 is
## the rightmost button in its row; rows count away from the corner.
##
## Which of gather's actions earn a button, and why:
##   gather    the whole game — mine a node, and (through HotBarInventory) place
##             the held building. Held.
##   attack    the only way to fight the enemy waves.
##   action    open a chest / crafting station; without it the crafting half of the
##             game is unreachable on a phone.
##   destroy   removes a misplaced building. Held, same as gather.
##   ITEM      cycles the hotbar selection. Not an action at all, but without it a
##             phone player is stuck on slot 1 forever and can never place a
##             building or swap to the sword.
##   inventory / skills / land   the three panels. They are the progression UI, and
##             on a phone they are also the only way to *close* themselves again,
##             so they stay on top of everything (see the mount order in main.tscn).
##
## Left off deliberately: `save` and `load` (debug bindings, and there are already
## Save/Load buttons in the camera HUD) and the mouse buttons (touch already
## emulates a left click).
const BUTTON_SPECS := [
	{"name": "GatherButton", "action": "gather", "label": "MINE", "big": true, "primary": true, "corner": "br", "row": 0, "col": 0},
	{"name": "AttackButton", "action": "attack", "label": "HIT", "big": true, "primary": false, "corner": "br", "row": 0, "col": 1},
	{"name": "ActionButton", "action": "action", "label": "USE", "big": false, "primary": false, "corner": "br", "row": 1, "col": 0},
	{"name": "DestroyButton", "action": "destroy", "label": "BREAK", "big": false, "primary": false, "corner": "br", "row": 1, "col": 1},
	{"name": "HotbarButton", "action": HOTBAR_CYCLE, "label": "ITEM", "big": false, "primary": false, "corner": "br", "row": 1, "col": 2},
	{"name": "SkillsButton", "action": "skills", "label": "SKILL", "big": false, "primary": false, "corner": "tr", "row": 0, "col": 0},
	{"name": "InventoryButton", "action": "inventory", "label": "BAG", "big": false, "primary": false, "corner": "tr", "row": 0, "col": 1},
	{"name": "LandButton", "action": "land", "label": "LAND", "big": false, "primary": false, "corner": "tr", "row": 0, "col": 2},
]

var _joystick: Control

## The generated button Controls, in BUTTON_SPECS order, and their metadata.
var _buttons: Array[Control] = []
var _button_action: Dictionary = {}

## touch index -> the button that finger is currently holding.
var _held: Dictionary = {}

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

	_build_buttons()
	_layout()

	var vp := get_viewport()
	if vp != null and not vp.size_changed.is_connected(_layout):
		vp.size_changed.connect(_layout)

	_touch_available = DisplayServer.is_touchscreen_available()
	_apply_visibility()


func _process(_delta: float) -> void:
	# DisplayServer.is_touchscreen_available() is a query, not a signal, and the
	# self-test harness's `set-feature --touchscreen true` flips it at runtime
	# (it drives Input.set_emulate_touch_from_mouse). Reading it once in _ready()
	# would mean the overlay never appears for a desktop test run.
	var now := DisplayServer.is_touchscreen_available()
	if now != _touch_available:
		_touch_available = now
		_apply_visibility()


## Shows the overlay regardless of whether a touchscreen is reported. For tests and
## for eyeballing the layout on desktop.
func set_forced_visible(on: bool) -> void:
	_force_visible = on
	_apply_visibility()


func is_forced_visible() -> bool:
	return _force_visible


## The generated Control for an InputMap action (or HOTBAR_CYCLE), or null.
func get_button_for(action: String) -> Control:
	for button in _buttons:
		if _button_action.get(button, "") == action:
			return button
	return null


## Every action this overlay can send, HOTBAR_CYCLE included.
func get_actions() -> Array[String]:
	var out: Array[String] = []
	for button in _buttons:
		out.append(str(_button_action.get(button, "")))
	return out


func _apply_visibility() -> void:
	var want := _force_visible or _touch_available
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
func handle_touch_event(event: InputEvent) -> bool:
	if not visible:
		return false

	var touch := event as InputEventScreenTouch
	if touch != null:
		if touch.pressed:
			var button := _button_at(touch.position)
			if button != null:
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
			if over != null:
				_press(drag.index, over)
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
	var action: String = _button_action.get(button, "")
	if action == HOTBAR_CYCLE:
		# A one-shot: the slot changes on finger-down and there is nothing to hold.
		_held[index] = button
		_set_pressed_look(button, true)
		_cycle_hotbar()
		action_sent.emit(HOTBAR_CYCLE, true)
		return

	_held[index] = button
	_set_pressed_look(button, true)
	send_action(action, true)


func _release(index: int) -> void:
	var button: Control = _held[index]
	_held.erase(index)

	# A second finger may still be on the same button.
	if _held.values().has(button):
		return

	_set_pressed_look(button, false)
	var action: String = _button_action.get(button, "")
	if action == HOTBAR_CYCLE:
		action_sent.emit(HOTBAR_CYCLE, false)
		return

	send_action(action, false)


func _release_all() -> void:
	# keys() is a fresh array, so erasing inside the loop is safe.
	for index in _held.keys():
		_release(index)


func _set_pressed_look(button: Control, down: bool) -> void:
	button.modulate = PRESSED_MODULATE if down else Color.WHITE


## Feeds one half of an InputMap action into the engine, exactly as the keyboard
## would. Public because the gather/destroy holds are the part most worth driving
## from a test or a devtools verb.
func send_action(action: String, pressed: bool) -> void:
	if action == "" or action == HOTBAR_CYCLE:
		return
	if not InputMap.has_action(action):
		push_error("MobileControls: no InputMap action named '%s'" % action)
		return

	var event := InputEventAction.new()
	event.action = action
	event.pressed = pressed
	Input.parse_input_event(event)
	action_sent.emit(action, pressed)


## Advances the hotbar selection by one slot. hot_bar_inventory.gd selects from
## _unhandled_key_input on KEY_1..KEY_6 and publishes no InputMap action, so
## sending the same key it already listens for is the only way to drive it without
## copying its selection logic in here. The current slot is read back off the
## hotbar rather than tracked locally, so number keys and this button stay in sync.
func _cycle_hotbar() -> void:
	var current := 0
	var hotbar := _find_hotbar()
	if hotbar != null:
		var idx: Variant = hotbar.get("selected_index")
		if typeof(idx) == TYPE_INT:
			current = idx

	var next: int = posmod(current + 1, HOTBAR_SLOT_COUNT)

	var down := InputEventKey.new()
	down.keycode = KEY_1 + next
	down.physical_keycode = KEY_1 + next
	down.pressed = true
	Input.parse_input_event(down)

	# Nothing binds KEY_1..KEY_6, but leaving a key logically down is still a trap.
	var up := InputEventKey.new()
	up.keycode = KEY_1 + next
	up.physical_keycode = KEY_1 + next
	up.pressed = false
	Input.parse_input_event(up)


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
		label.add_theme_color_override("font_color", COLOR_LABEL)
		button.add_child(label)
		label.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)

		add_child(button)
		_buttons.append(button)
		_button_action[button] = str(spec["action"])


func _button_style(primary: bool) -> StyleBoxFlat:
	var style := StyleBoxFlat.new()
	style.bg_color = COLOR_BG
	style.border_color = COLOR_BORDER_PRIMARY if primary else COLOR_BORDER
	style.set_border_width_all(3 if primary else 2)
	style.set_corner_radius_all(16)
	return style


## Sizes and positions everything from the current viewport, because the project
## runs with window/stretch/mode="disabled": the viewport is the device's real
## pixel size, so a phone gets a viewport a fraction of the desktop one's and any
## fixed pixel layout would come out unusable at one end or the other.
func _layout() -> void:
	var vp := get_viewport_rect().size
	if vp.x <= 0.0 or vp.y <= 0.0:
		return

	var shortest := minf(vp.x, vp.y)
	var big := clampf(shortest * 0.20, 52.0, 148.0)
	var small := big * 0.68
	var pad := big * 0.16
	var margin := clampf(shortest * 0.035, 10.0, 40.0)

	_layout_row("br", 0, vp, big, small, pad, margin)
	_layout_row("br", 1, vp, big, small, pad, margin)
	_layout_row("tr", 0, vp, big, small, pad, margin)

	if _joystick != null:
		var scale_factor := clampf(shortest / 720.0, 0.45, 1.25)
		_joystick.set_anchors_preset(Control.PRESET_TOP_LEFT)
		_joystick.size = JOYSTICK_SIZE
		_joystick.scale = Vector2(scale_factor, scale_factor)
		_joystick.position = Vector2(margin, vp.y - margin - JOYSTICK_SIZE.y * scale_factor)
		# Both zones are compared against a screen-space vector inside the addon, so
		# they have to be scaled alongside the control or the tip stops where the art
		# does not.
		_joystick.set("clampzone_size", JOYSTICK_CLAMPZONE * scale_factor)
		_joystick.set("deadzone_size", JOYSTICK_DEADZONE * scale_factor)


## Lays one row out from the right edge, walking leftwards in `col` order.
func _layout_row(corner: String, row: int, vp: Vector2, big: float, small: float, pad: float, margin: float) -> void:
	var row_height := big if row == 0 and corner == "br" else small

	var top := 0.0
	if corner == "br":
		# Row 0 sits on the bottom margin; each further row stacks above it.
		top = vp.y - margin - big
		if row > 0:
			top -= float(row) * (small + pad)
	else:
		top = margin + float(row) * (small + pad)

	var right := vp.x - margin
	for spec in BUTTON_SPECS:
		if str(spec["corner"]) != corner or int(spec["row"]) != row:
			continue

		var button := _button_named(str(spec["name"]))
		if button == null:
			continue

		var side := big if spec["big"] == true else small
		# `col` is authored left-to-right within the row, so walking BUTTON_SPECS in
		# order and consuming from the right edge places them correctly.
		right -= side
		button.position = Vector2(right, top + (row_height - side) * 0.5)
		button.size = Vector2(side, side)
		right -= pad

		var label := button.get_node_or_null("Label") as Label
		if label != null:
			label.add_theme_font_size_override("font_size", maxi(9, int(side * 0.22)))


func _button_named(button_name: String) -> Control:
	for button in _buttons:
		if button.name == button_name:
			return button
	return null
