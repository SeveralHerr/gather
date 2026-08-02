extends RefCounted

## Covers the touch overlay that makes the web build playable on a phone.
##
## The one that actually matters is test_gather_button_sends_a_press_and_a_release:
## `gather` is a hold (press starts ResourceManager2's timer, release is what calls
## stop_removing_resource), so a button that only fired on tap would leave the
## player mining forever. Everything else here is guarding the wiring around it —
## that each button names an action the InputMap really has, and that losing focus
## mid-hold lets go instead of latching the action down.

const SCENE_PATH := "res://ui/mobile_controls.tscn"

var _T

var controls
var sent: Array = []


func teardown() -> void:
	if controls != null and is_instance_valid(controls):
		_T.free_ui(controls)
	controls = null
	sent = []

	# Release anything a failed test left latched, so it cannot leak into the next
	# one. Read off BUTTON_SPECS rather than a hand-listed copy of it: a new button
	# that a test fails while holding would otherwise stay held for the whole suite.
	for spec in MobileControls.BUTTON_SPECS:
		var action := str(spec["action"])
		if InputMap.has_action(action) and Input.is_action_pressed(action):
			Input.action_release(action)


## Instantiates the overlay inside a SubViewport and forces it visible: headless
## reports no touchscreen, and the overlay hides itself when there is none.
func _make_overlay(viewport_size: Vector2i = Vector2i(1280, 720)):
	var node = await _T.instantiate_ui(SCENE_PATH, viewport_size)
	controls = node
	if controls != null:
		controls.set_forced_visible(true)
		controls.action_sent.connect(_on_action_sent)
	return controls


func _on_action_sent(action: String, pressed: bool) -> void:
	sent.append([action, pressed])


func _touch(index: int, at: Vector2, pressed: bool) -> InputEventScreenTouch:
	var event := InputEventScreenTouch.new()
	event.index = index
	event.position = at
	event.pressed = pressed
	return event


func _center_of(action: String) -> Vector2:
	return controls.get_button_for(action).get_global_rect().get_center()


func test_overlay_instantiates_with_a_joystick_bound_to_gathers_move_actions() -> String:
	var overlay = await _make_overlay()

	var err: String = _T.assert_true(overlay != null, "the overlay scene instantiates")
	if err != "":
		return err

	var joystick: Node = overlay.get_node_or_null("VirtualJoystick")
	err = _T.assert_true(joystick != null, "the addon joystick is mounted as a child")
	if err != "":
		return err

	# AtomicRobot's joystick drives ui_left/ui_right/...; gather has its own actions
	# and getting this wrong is a silently unmoving player, not an error.
	for direction in ["left", "right", "up", "down"]:
		err = _T.assert_eq(
			joystick.get("action_" + direction), "move_" + direction,
			"joystick drives move_%s" % direction)
		if err != "":
			return err

	return ""


func test_gather_button_sends_a_press_and_a_release() -> String:
	var overlay = await _make_overlay()

	var button: Control = overlay.get_button_for("gather")
	var err: String = _T.assert_true(button != null, "there is a gather button")
	if err != "":
		return err

	var at := _center_of("gather")

	err = _T.assert_true(overlay.handle_touch_event(_touch(0, at, true)), "the press lands on the button")
	if err != "":
		return err
	err = _T.assert_eq(sent.size(), 1, "the press sends exactly one action")
	if err != "":
		return err
	err = _T.assert_eq(sent[0], ["gather", true], "finger down presses gather")
	if err != "":
		return err

	err = _T.assert_true(overlay.handle_touch_event(_touch(0, at, false)), "the release is consumed too")
	if err != "":
		return err
	err = _T.assert_eq(sent.size(), 2, "the release sends exactly one more action")
	if err != "":
		return err
	# Without this half, Player._gather_input_release never runs and
	# ResourceManager2.stop_removing_resource() is never called.
	return _T.assert_eq(sent[1], ["gather", false], "finger up releases gather")


func test_a_held_button_latches_the_real_input_action() -> String:
	var overlay = await _make_overlay()
	var at := _center_of("gather")

	var tree: SceneTree = Engine.get_main_loop() as SceneTree

	overlay.handle_touch_event(_touch(0, at, true))
	await tree.process_frame
	var err: String = _T.assert_true(Input.is_action_pressed("gather"), "the engine sees gather held down")
	if err != "":
		return err

	overlay.handle_touch_event(_touch(0, at, false))
	await tree.process_frame
	return _T.assert_false(Input.is_action_pressed("gather"), "letting go clears the action")


func test_every_button_names_an_action_the_input_map_has() -> String:
	var overlay = await _make_overlay()

	var actions: Array = overlay.get_actions()
	var err: String = _T.assert_gte(actions.size(), 5, "at least the five required verbs got buttons")
	if err != "":
		return err

	for action in actions:
		# The hotbar cycle is deliberately not an InputMap action: hot_bar_inventory
		# selects slots from raw KEY_1..KEY_6, so that button sends a key instead.
		if action == MobileControls.HOTBAR_CYCLE:
			continue
		err = _T.assert_true(InputMap.has_action(action), "'%s' is a real InputMap action" % action)
		if err != "":
			return err

	for required in ["gather", "attack", "action", "inventory", "skills"]:
		err = _T.assert_true(actions.has(required), "'%s' has a button" % required)
		if err != "":
			return err

	return ""


func test_losing_focus_releases_a_held_button() -> String:
	var overlay = await _make_overlay()

	overlay.handle_touch_event(_touch(0, _center_of("gather"), true))
	sent = []

	# Backgrounding the app (or switching browser tab) never delivers the matching
	# touch release, so the overlay has to let go by itself.
	overlay.notification(Node.NOTIFICATION_APPLICATION_FOCUS_OUT)

	var err: String = _T.assert_eq(sent.size(), 1, "focus loss sends one action")
	if err != "":
		return err
	return _T.assert_eq(sent[0], ["gather", false], "focus loss releases the held gather")


func test_buttons_stay_inside_a_small_phone_viewport() -> String:
	# stretch mode is "disabled", so on a phone the viewport really is this small
	# and a fixed pixel layout would push the cluster off screen.
	var overlay = await _make_overlay(Vector2i(720, 360))

	# Read the bound back off the viewport rather than restating the size, so the
	# assertion cannot drift from the viewport the overlay actually laid itself out in.
	var screen := Rect2(Vector2.ZERO, overlay.get_viewport_rect().size)

	for action in overlay.get_actions():
		var rect: Rect2 = overlay.get_button_for(action).get_global_rect()
		var err: String = _T.assert_true(
			screen.encloses(rect),
			"'%s' is on screen at %s (got %s)" % [action, str(screen.size), str(rect)])
		if err != "":
			return err

	return ""


func test_hidden_overlay_ignores_touches() -> String:
	var overlay = await _make_overlay()
	var at := _center_of("gather")

	overlay.set_forced_visible(false)

	var err: String = _T.assert_false(overlay.visible, "no touchscreen means no overlay")
	if err != "":
		return err
	# A desktop run must not have half the screen quietly eating clicks.
	err = _T.assert_false(overlay.handle_touch_event(_touch(0, at, true)), "a hidden overlay consumes nothing")
	if err != "":
		return err
	return _T.assert_eq(sent.size(), 0, "a hidden overlay sends nothing")
