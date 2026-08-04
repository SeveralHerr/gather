extends RefCounted

## Covers the HUD toolbar — the BAG / SKILLS / LAND / SAVES buttons that are the only
## on-screen way into the game's four panels.
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
	# neither had any on-screen way in before it. `saves` is here for a harder reason:
	# `[` and `]` are keyboard-only and Systems/SaveLoad is an empty invisible Control,
	# so this button is the only affordance the save system has at all on desktop.
	for required in ["inventory", "skills", "land", "saves"]:
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
	# 720 wide is roomy for this row; the narrow case is the portrait test below.
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


## Every button reachable on the narrowest screen the game expects, however many there are.
##
## 390x844 is a phone held upright. The test above cannot stand in for it: `UiTheme.scale_for()`
## clamps at SCALE_MIN, so 390 and 720 both land on the same 0.85 factor and produce the *same*
## buttons — but one of them has 720px to put them in and the other has 390.
##
## This used to be `test_a_fourth_button_still_fits_a_portrait_phone`, a width *budget*: the row
## was an HBoxContainer anchored top-right with `grow_horizontal = GROW_DIRECTION_BEGIN`, so an
## over-wide row neither clipped nor wrapped — the leftmost button simply ended up off the left
## edge, reachable by nothing and announced by nothing. Four buttons cleared 390px by about two
## pixels, which was never a budget so much as a coincidence, and the fifth (`quests`) blew it.
##
## The row is an `HFlowContainer` now, so it wraps to a second line instead and there is no
## budget to spend. What is asserted is therefore the property that actually matters and always
## did — every button is fully on screen — rather than the proxy that only held while they
## happened to fit on one line. A sixth button makes the strip taller; it can no longer make one
## disappear.
func test_every_button_is_reachable_on_a_portrait_phone() -> String:
	var strip := await _make_toolbar(Vector2i(390, 844))
	var tree: SceneTree = Engine.get_main_loop() as SceneTree
	strip.visible = true

	var screen := Rect2(Vector2.ZERO, strip.get_viewport_rect().size)

	for action in strip.get_actions():
		var rect: Rect2 = strip.get_button_for(action).get_global_rect()
		var err: String = _T.assert_true(
			screen.encloses(rect),
			"'%s' fits a portrait phone at %s (got %s)" % [action, str(screen.size), str(rect)])
		if err != "":
			return err

	# ...and still when the faces are at their widest. Two buttons rewrite themselves when
	# something is banked ("SKILLS +99  [K]", "TASKS +9  [J]"), and `style_button` adds 8px of
	# unscaled content margin per side, so the widest the strip ever gets is not the width it has
	# while idle. A layout that only holds for the idle strip fails in the game, on the very
	# screen the player earned a level on.
	strip.get_button_for("skills").text = "SKILLS +99  [K]"
	strip.get_button_for("quests").text = "TASKS +9  [J]"
	await tree.process_frame
	await tree.process_frame

	for action in strip.get_actions():
		var rect: Rect2 = strip.get_button_for(action).get_global_rect()
		var err: String = _T.assert_true(
			screen.encloses(rect),
			"the loaded '%s' is still on screen (got %s of %s)"
				% [action, str(rect), str(screen.size)])
		if err != "":
			return err

	return ""


## The height the strip reports has to cover every button it drew, on any screen.
##
## `skill_tree_ui.gd`'s banked-points badge parks itself under `occupied_top_height()`, so a
## strip that reported less than its real extent would have the badge drawn straight through a
## button. That was a safe assumption while the row was one line of fixed height; it stopped
## being one when the row became an `HFlowContainer` that wraps, because
## `get_combined_minimum_size()` on a flow container is width-dependent and answers for whatever
## width it had when asked — the one-line height, for a strip about to become two.
##
## Asserted on both a phone and a desktop window, because which of the two wraps depends on font
## metrics and is not itself worth pinning; what is worth pinning is that the answer covers the
## buttons either way.
func test_the_reported_height_covers_every_button() -> String:
	for size in [Vector2i(390, 844), Vector2i(1280, 720)]:
		var strip := await _make_toolbar(size)
		strip.visible = true

		var reported := strip.occupied_top_height()
		var err: String = _T.assert_gt(
			reported, 0.0, "a visible strip at %s reports a height" % str(size))
		if err != "":
			return err

		for action in strip.get_actions():
			var rect: Rect2 = strip.get_button_for(action).get_global_rect()
			var covered: String = _T.assert_gte(
				reported, rect.end.y,
				"'%s' at %s sits within the reported %.1f (its bottom is %.1f)"
					% [action, str(size), reported, rect.end.y])
			if covered != "":
				return covered

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
