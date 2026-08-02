extends RefCounted

## Layout guards for the crafting panel.
##
## The panel this replaced lived under Player/Camera2D/UI — world space at the
## camera's ~5x zoom — with every offset hand-tuned to a 1152x648 window and every
## child carrying a compensating scale. It could not survive a resize, and nothing
## caught that because a wrongly-sized panel still parses, still lints and still
## opens. These tests are the thing that would have.

var _T

const SIZES := [Vector2i(480, 800), Vector2i(1280, 720), Vector2i(1920, 1080), Vector2i(2560, 1440)]


func _panel(viewport_size: Vector2i) -> CraftingUi:
	var panel := CraftingUi.new()
	# There is no .tscn — the panel builds itself in code, so instantiate_ui takes
	# the node. Without it headless pumps no frames and every size stays (0, 0).
	return await _T.instantiate_ui(panel, viewport_size) as CraftingUi


func test_the_panel_fits_inside_every_window_size() -> String:
	for viewport_size in SIZES:
		var panel := await _panel(viewport_size)
		panel.set_open(true)
		await panel.get_tree().process_frame

		var frame: PanelContainer = panel._frame
		var err: String = _T.assert_true(
			frame.size.x <= float(viewport_size.x) and frame.size.y <= float(viewport_size.y),
			"panel %s fits inside a %s window" % [frame.size, viewport_size])
		_T.free_ui(panel)
		if err != "":
			return err
	return ""


func test_the_panel_is_centred_rather_than_pinned_to_an_offset() -> String:
	var viewport_size := Vector2i(1920, 1080)
	var panel := await _panel(viewport_size)
	panel.set_open(true)
	await panel.get_tree().process_frame

	var frame: PanelContainer = panel._frame
	var frame_centre := frame.global_position + frame.size * 0.5
	var screen_centre := Vector2(viewport_size) * 0.5
	var err: String = _T.assert_true(
		frame_centre.distance_to(screen_centre) < 2.0,
		"panel centre %s sits on the screen centre %s" % [frame_centre, screen_centre])
	_T.free_ui(panel)
	return err


func test_a_narrow_window_gets_a_smaller_panel_not_an_overflowing_one() -> String:
	var small := await _panel(Vector2i(640, 480))
	small.set_open(true)
	await small.get_tree().process_frame
	var small_width: float = small._frame.size.x
	var compact: bool = small._compact
	_T.free_ui(small)

	var large := await _panel(Vector2i(1920, 1080))
	large.set_open(true)
	await large.get_tree().process_frame
	var large_width: float = large._frame.size.x
	_T.free_ui(large)

	var err: String = _T.assert_true(small_width < large_width,
		"a 640px window gets a narrower panel (%s) than a 1920px one (%s)" % [small_width, large_width])
	if err != "":
		return err
	# Below the threshold the detail pane cannot sit beside the grid, so the panel
	# becomes two pages rather than reflowing into an unreadable column.
	return _T.assert_true(compact, "a 640px window puts the panel into compact mode")


func test_the_grid_uses_more_columns_when_there_is_room() -> String:
	# A phone viewport, the case gather-zxl is about. 800x600 would not prove anything
	# here: it is already narrow enough to go compact, and a compact panel hands the
	# grid the full width back, so it lands on the same column count as a desktop one.
	var small := await _panel(Vector2i(480, 800))
	var small_columns: int = small._grid.columns
	_T.free_ui(small)

	var large := await _panel(Vector2i(1920, 1080))
	var large_columns: int = large._grid.columns
	_T.free_ui(large)

	return _T.assert_gt(large_columns, small_columns,
		"a wide window fits more recipe cards per row (%d vs %d)" % [large_columns, small_columns])


func test_closing_the_panel_hands_input_back() -> String:
	# Set, never toggled: the handler this replaced flipped disable_input, so a panel
	# opened twice left the player frozen with no menu on screen.
	var panel := await _panel(Vector2i(1280, 720))
	panel.input_manager = InputManager.new()

	panel.set_open(true)
	panel.set_open(true)
	panel.set_open(false)

	var disabled: bool = panel.input_manager.disable_input
	panel.input_manager.free()
	_T.free_ui(panel)

	return _T.assert_false(disabled, "input is enabled again after the panel closes")
