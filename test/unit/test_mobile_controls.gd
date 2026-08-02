extends RefCounted

## Covers the touch overlay that makes the web build playable on a phone.
##
## Two things here actually matter and everything else guards the wiring around them.
##
## The first is that a hold sends *both halves*: `gather` is a hold (press starts
## ResourceManager2's timer, release is what calls stop_removing_resource), so a
## button that only fired on tap would leave the player mining forever.
##
## The second arrived with the contextual primary button (gather-mxf). That one
## button resolves to `gather` or `attack` from live world state, and the world moves
## while a finger is down — the node gets mined to nothing, a skeleton walks up. If
## the release re-resolved, a press that sent `gather` could release `attack`, the
## engine would never see the gather release, and the mining timer would run forever.
## That is gather-3zg reached from a new direction, and
## test_a_context_flip_mid_hold_still_releases_the_action_it_pressed is the assertion
## that stops it coming back. `primary_resolver` exists purely so a test can flip the
## context between the two halves of a press on demand.

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
	# one. Built from BUTTON_SPECS rather than hand-listed, so a button added later
	# that a test fails while holding cannot stay held for the rest of the suite — and
	# the primary button's sentinel is expanded into the real actions it sends, which
	# a naive walk over the table would miss entirely.
	var actions: Array = []
	for spec in MobileControls.BUTTON_SPECS:
		if str(spec["action"]) == MobileControls.PRIMARY_ACTION:
			actions.append_array(MobileControls.PRIMARY_ACTIONS)
		else:
			actions.append(str(spec["action"]))

	for action in actions:
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


## Pins the primary button's resolution to one answer, so a test drives the merge
## rather than whatever the (absent) world would say.
func _pin(action: String, label: String) -> void:
	controls.primary_resolver = func(): return {"action": action, "label": label}


# --- construction -------------------------------------------------------------

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


func test_every_button_names_an_action_the_input_map_has() -> String:
	var overlay = await _make_overlay()

	var actions: Array = overlay.get_actions()

	# Every entry, with no exceptions carved out. The ITEM button used to need one:
	# it drove the hotbar by forging raw KEY_1..KEY_6 and so named no action at all.
	# It is gone, and with it the only non-InputMap "action" this overlay ever had.
	for action in actions:
		var err: String = _T.assert_true(
			InputMap.has_action(action), "'%s' is a real InputMap action" % action)
		if err != "":
			return err

	for required in ["gather", "attack", "action", "destroy", "inventory", "skills", "land"]:
		var err: String = _T.assert_true(actions.has(required), "'%s' is reachable" % required)
		if err != "":
			return err

	return ""


func test_mine_and_hit_are_now_one_button() -> String:
	var overlay = await _make_overlay()

	var gather_button: Control = overlay.get_button_for("gather")
	var attack_button: Control = overlay.get_button_for("attack")

	var err: String = _T.assert_true(gather_button != null, "asking for gather finds a button")
	if err != "":
		return err
	# The bead: a child cannot tell MINE from HIT, so there is only one of them now.
	err = _T.assert_true(
		gather_button == attack_button, "gather and attack are the same button")
	if err != "":
		return err

	# Six buttons, down from eight: the primary, USE, the three panels and BREAK.
	err = _T.assert_eq(
		MobileControls.BUTTON_SPECS.size(), 6, "the overlay draws six buttons")
	if err != "":
		return err

	var world_actions := 0
	for spec in MobileControls.BUTTON_SPECS:
		if str(spec["corner"]) == "br":
			world_actions += 1
	# Only the primary and USE sit under the thumb. BREAK moved to the far corner and
	# ITEM is gone entirely.
	return _T.assert_eq(world_actions, 2, "two buttons in the thumb cluster")


func test_break_is_out_of_the_thumbs_way_but_still_reachable() -> String:
	var overlay = await _make_overlay()

	var primary: Control = overlay.get_button_for("gather")
	var destroy: Control = overlay.get_button_for("destroy")

	var err: String = _T.assert_true(destroy != null, "BREAK still has a button")
	if err != "":
		return err

	# A mis-tap on BREAK deletes a building the player meant to keep, so it must not
	# be adjacent to the button a thumb aims at constantly. Assert the separation
	# rather than the corner name: the point is the distance, not the table row.
	var gap: float = primary.get_global_rect().position.y - destroy.get_global_rect().end.y
	return _T.assert_gt(
		gap, primary.get_global_rect().size.y,
		"BREAK is more than one button-height clear of the primary (gap %.1f)" % gap)


# --- the resolution rule ------------------------------------------------------

## The table in resolve_primary()'s doc comment, walked in both directions. Static
## and pure, so no world is needed to reach every branch.
func test_the_primary_button_resolves_from_what_is_held() -> String:
	var pickaxe := GameItemPickaxe.new(
		Vector2i.ZERO, 4, Types.Item.WoodPickaxe, 1, false, "Wooden Pickaxe")
	var sword := GameItemSword.new(Vector2i.ZERO, 4, Types.Item.Sword, 1, false, "Sword")
	var food := GameItemConsumable.new(
		Vector2i.ZERO, 4, Types.Item.Food, 1, false, "Food", Vector2i.ZERO, false, 4)
	var wall := GameItemWall2.new(Vector2i.ZERO, 4, Types.Item.WoodWall, 1, true, "Wood Wall")
	var net := GameItemNet.new(Vector2i.ZERO, 4, Types.Item.Net, 1, false, "Net")

	# [item, enemy_in_reach, action, label]
	var cases := [
		# A pickaxe with nothing near mines. This is the default face of the button.
		[pickaxe, false, "gather", "MINE"],
		# ...and the same pickaxe yields to something standing on top of the player.
		# This is the trade-off resolve_primary() documents: a child holding the
		# default tool has to be able to fight back.
		[pickaxe, true, "attack", "HIT"],
		# An empty slot behaves exactly like the pickaxe.
		[null, false, "gather", "MINE"],
		[null, true, "attack", "HIT"],
		# A weapon is a statement of intent and never defers.
		[sword, false, "attack", "HIT"],
		[sword, true, "attack", "HIT"],
		# Food must stay reachable with an enemy in reach — that is when it is needed.
		[food, false, "gather", "EAT"],
		[food, true, "gather", "EAT"],
		# Building is `gather` too, and walling a monster out is a fair answer to it.
		[wall, false, "gather", "BUILD"],
		[wall, true, "gather", "BUILD"],
		[net, false, "gather", "NET"],
		[net, true, "gather", "NET"],
	]

	for row in cases:
		var got: Dictionary = MobileControls.resolve_primary(row[0], row[1])
		var who: String = "nothing" if row[0] == null else str(row[0].name)
		var err: String = _T.assert_eq(
			got.get("action"), row[2],
			"holding %s with enemy_in_reach=%s sends %s" % [who, str(row[1]), row[2]])
		if err != "":
			return err
		err = _T.assert_eq(
			got.get("label"), row[3],
			"holding %s with enemy_in_reach=%s reads %s" % [who, str(row[1]), row[3]])
		if err != "":
			return err

	return ""


func test_the_label_says_what_the_button_will_do() -> String:
	var overlay = await _make_overlay()

	var label: Label = overlay.get_button_for("gather").get_node_or_null("Label") as Label
	var err: String = _T.assert_true(label != null, "the primary button carries a label")
	if err != "":
		return err

	_pin("gather", "MINE")
	overlay.refresh_primary()
	err = _T.assert_eq(label.text, "MINE", "a mining context reads MINE")
	if err != "":
		return err
	err = _T.assert_eq(overlay.primary_label(), "MINE", "and reports it")
	if err != "":
		return err

	# A button whose meaning changes silently is worse than two buttons.
	_pin("attack", "HIT")
	overlay.refresh_primary()
	err = _T.assert_eq(label.text, "HIT", "an enemy in reach reads HIT")
	if err != "":
		return err
	return _T.assert_eq(overlay.primary_action(), "attack", "and would send attack")


func test_the_label_is_frozen_while_the_button_is_held() -> String:
	var overlay = await _make_overlay()

	var label: Label = overlay.get_button_for("gather").get_node_or_null("Label") as Label

	_pin("gather", "MINE")
	overlay.refresh_primary()
	overlay.handle_touch_event(_touch(0, _center_of("gather"), true))

	# The context poll keeps running during a hold. It must not repaint the face,
	# because the release is going to send the *latched* action and a label saying
	# otherwise would be a lie about what the finger is currently doing.
	_pin("attack", "HIT")
	overlay.refresh_primary()

	return _T.assert_eq(label.text, "MINE", "the face does not change under a finger")


# --- press / release pairing --------------------------------------------------

func test_gather_button_sends_a_press_and_a_release() -> String:
	var overlay = await _make_overlay()
	_pin("gather", "MINE")

	var button: Control = overlay.get_button_for("gather")
	var err: String = _T.assert_true(button != null, "there is a primary button")
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


func test_a_context_flip_mid_hold_still_releases_the_action_it_pressed() -> String:
	var overlay = await _make_overlay()
	var at := _center_of("gather")

	# Mining -> a skeleton wanders into reach while the thumb is still down. The
	# release must be a gather release; anything else strands ResourceManager2's hold
	# timer with nothing left to stop it.
	_pin("gather", "MINE")
	overlay.handle_touch_event(_touch(0, at, true))
	_pin("attack", "HIT")
	overlay.handle_touch_event(_touch(0, at, false))

	var err: String = _T.assert_eq(sent.size(), 2, "one press, one release")
	if err != "":
		return err
	err = _T.assert_eq(sent[0], ["gather", true], "the press was a gather")
	if err != "":
		return err
	err = _T.assert_eq(sent[1], ["gather", false], "the release is the SAME action")
	if err != "":
		return err

	# And the other direction: fighting, and the enemy dies (or walks off) mid-swing.
	sent = []
	_pin("attack", "HIT")
	overlay.handle_touch_event(_touch(0, at, true))
	_pin("gather", "MINE")
	overlay.handle_touch_event(_touch(0, at, false))

	err = _T.assert_eq(sent.size(), 2, "one press, one release the other way round")
	if err != "":
		return err
	err = _T.assert_eq(sent[0], ["attack", true], "the press was an attack")
	if err != "":
		return err
	err = _T.assert_eq(sent[1], ["attack", false], "the release is the SAME action")
	if err != "":
		return err

	# The latch is released with the finger, so the next press resolves afresh.
	sent = []
	overlay.handle_touch_event(_touch(0, at, true))
	overlay.handle_touch_event(_touch(0, at, false))
	return _T.assert_eq(sent, [["gather", true], ["gather", false]], "the next press re-resolves")


func test_sliding_off_the_button_releases_what_it_pressed() -> String:
	var overlay = await _make_overlay()
	var at := _center_of("gather")
	var away := Vector2(-100, -100)

	_pin("gather", "MINE")
	overlay.handle_touch_event(_touch(0, at, true))

	# Sliding off releases; the release still has to be the gather half.
	_pin("attack", "HIT")
	var drag := InputEventScreenDrag.new()
	drag.index = 0
	drag.position = away
	overlay.handle_touch_event(drag)

	var err: String = _T.assert_eq(sent.size(), 2, "sliding off releases")
	if err != "":
		return err
	return _T.assert_eq(sent[1], ["gather", false], "and releases what it pressed")


func test_a_held_button_latches_the_real_input_action() -> String:
	var overlay = await _make_overlay()
	_pin("gather", "MINE")
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


func test_losing_focus_releases_a_held_button() -> String:
	var overlay = await _make_overlay()
	_pin("gather", "MINE")

	overlay.handle_touch_event(_touch(0, _center_of("gather"), true))
	sent = []

	# Backgrounding the app (or switching browser tab) never delivers the matching
	# touch release, so the overlay has to let go by itself — and, again, of the
	# action it actually pressed, whatever the world says by then.
	_pin("attack", "HIT")
	overlay.notification(Node.NOTIFICATION_APPLICATION_FOCUS_OUT)

	var err: String = _T.assert_eq(sent.size(), 1, "focus loss sends one action")
	if err != "":
		return err
	return _T.assert_eq(sent[0], ["gather", false], "focus loss releases the held gather")


# --- layout -------------------------------------------------------------------

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
