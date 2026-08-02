extends RefCounted

## Covers the HUD toolbar — the BAG / SKILLS / LAND buttons that are the only
## on-screen way into the game's three panels.
##
## The two that matter are test_the_key_hint_matches_the_real_binding and
## test_pressing_a_button_sends_both_halves_of_the_action. The first is the one a
## diff cannot catch: the face of the button prints "[K]" from a table in
## `hud_toolbar.gd`, while the binding lives in `project.godot`, so rebinding a key
## would leave every button quietly lying about itself. The second guards the same
## trap `mobile_controls.gd` documents — `input_manager.gd` answers these toggles on
## `is_action_released`, so a press without its release opens nothing and leaves the
## action latched down for whatever asks next.

var _T

var toolbar: HudToolbar
var host: Control
var sent: Array = []


func teardown() -> void:
	if host != null and is_instance_valid(host):
		_T.free_ui(host)
	host = null
	toolbar = null
	sent = []

	# Release anything a failed test left latched, so it cannot leak into the next.
	for spec in HudToolbar.BUTTON_SPECS:
		var action := str(spec["action"])
		if InputMap.has_action(action) and Input.is_action_pressed(action):
			Input.action_release(action)


## Builds the toolbar inside a stand-in for the UI CanvasLayer, because the strip
## reads its siblings: it hides behind MobileControls and behind any open PanelFrame.
func _make_toolbar(viewport_size: Vector2i = Vector2i(1280, 720)) -> HudToolbar:
	var root := Control.new()
	root.name = "UI"
	root.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)

	toolbar = HudToolbar.new()
	toolbar.name = "HudToolbar"
	root.add_child(toolbar)

	var made: Node = await _T.instantiate_ui(root, viewport_size)
	host = made as Control
	if toolbar != null:
		toolbar.action_sent.connect(_on_action_sent)
	return toolbar


func _on_action_sent(action: String, pressed: bool) -> void:
	sent.append([action, pressed])


## The keys `project.godot` really binds to `action`, as printable strings.
func _bound_keys(action: String) -> Array[String]:
	var keys: Array[String] = []
	for event in InputMap.action_get_events(action):
		var key := event as InputEventKey
		if key == null:
			continue
		var code := key.physical_keycode if key.physical_keycode != 0 else key.keycode
		keys.append(OS.get_keycode_string(code))
	return keys


func test_every_button_names_an_action_the_input_map_has() -> String:
	var strip := await _make_toolbar()

	var err: String = _T.assert_true(strip != null, "the toolbar builds")
	if err != "":
		return err

	for action in strip.get_actions():
		err = _T.assert_true(InputMap.has_action(action), "'%s' is a real InputMap action" % action)
		if err != "":
			return err
		err = _T.assert_true(strip.get_button_for(action) != null, "'%s' got a button" % action)
		if err != "":
			return err

	# The skill tree and the land economy are the whole reason this strip exists;
	# neither had any on-screen way in before it.
	for required in ["inventory", "skills", "land"]:
		err = _T.assert_true(strip.get_actions().has(required), "'%s' has a button" % required)
		if err != "":
			return err

	return ""


func test_the_key_hint_matches_the_real_binding() -> String:
	var strip := await _make_toolbar()

	for spec in HudToolbar.BUTTON_SPECS:
		var action := str(spec["action"])
		var hint := str(spec["key"])
		var bound := _bound_keys(action)

		var err: String = _T.assert_true(
			bound.has(hint),
			"the '%s' button prints [%s] and the InputMap binds %s" % [action, hint, str(bound)])
		if err != "":
			return err

		# ...and the hint is actually on the face, not only in the table.
		var button := strip.get_button_for(action)
		err = _T.assert_true(
			button.text.contains("[%s]" % hint) or button.text.contains(hint),
			"the '%s' button shows its key (got '%s')" % [action, button.text])
		if err != "":
			return err

	return ""


func test_pressing_a_button_sends_both_halves_of_the_action() -> String:
	var strip := await _make_toolbar()
	var tree: SceneTree = Engine.get_main_loop() as SceneTree

	strip.get_button_for("skills").pressed.emit()

	var err: String = _T.assert_eq(sent.size(), 2, "one press sends exactly two events")
	if err != "":
		return err
	err = _T.assert_eq(sent[0], ["skills", true], "the press half comes first")
	if err != "":
		return err
	# Without this half input_manager.gd never fires toggle_skills — it answers on
	# is_action_released — so the panel would not open at all.
	err = _T.assert_eq(sent[1], ["skills", false], "the release half follows")
	if err != "":
		return err

	await tree.process_frame
	return _T.assert_false(Input.is_action_pressed("skills"), "the action is not left latched down")


func test_the_strip_stays_inside_a_small_phone_viewport() -> String:
	# stretch mode is "disabled", so a phone really does report a viewport this
	# small and a fixed pixel layout would push the strip off the right edge.
	var strip := await _make_toolbar(Vector2i(720, 360))
	strip.visible = true

	var screen := Rect2(Vector2.ZERO, strip.get_viewport_rect().size)

	for action in strip.get_actions():
		var rect: Rect2 = strip.get_button_for(action).get_global_rect()
		var err: String = _T.assert_true(
			screen.encloses(rect),
			"'%s' is on screen at %s (got %s)" % [action, str(screen.size), str(rect)])
		if err != "":
			return err

	return ""


func test_the_strip_reports_the_corner_it_occupies() -> String:
	var strip := await _make_toolbar()

	var occupied := strip.occupied_top_height()
	var err: String = _T.assert_gt(
		occupied, 0.0, "a visible strip reports the height it covers")
	if err != "":
		return err

	# skill_tree_ui.gd parks its banked-points badge under this number. A stale zero
	# would draw the badge straight through the buttons, and nothing in a diff of
	# either file would show it.
	var button_bottom: float = strip.get_button_for("land").get_global_rect().end.y
	err = _T.assert_gte(
		occupied, button_bottom,
		"the reported height clears the buttons (bottom %s)" % str(button_bottom))
	if err != "":
		return err

	strip.visible = false
	return _T.assert_float_eq(
		strip.occupied_top_height(), 0.0, 0.01, "a hidden strip occupies nothing")


func test_an_open_panel_hides_the_strip() -> String:
	var strip := await _make_toolbar()
	var tree: SceneTree = Engine.get_main_loop() as SceneTree

	var err: String = _T.assert_true(strip.visible, "the strip is up during play")
	if err != "":
		return err

	# A sibling panel, built the way every panel in the game builds one.
	var panel := Control.new()
	panel.name = "FakePanel"
	strip.get_parent().add_child(panel)

	var frame := PanelFrame.new()
	frame.setup("TEST")
	panel.add_child(frame)
	# The strip scans for frames when it is built; this one arrived afterwards.
	strip.watch_panels()
	await tree.process_frame

	# Draw order cannot settle this: the strip is added to UI after every panel, so
	# it paints on top of the backdrop unless it takes itself away.
	frame.open()
	await tree.process_frame
	err = _T.assert_false(strip.visible, "an open panel hides the strip")
	if err != "":
		return err

	frame.close()
	await tree.process_frame
	return _T.assert_true(strip.visible, "closing the panel brings it back")
