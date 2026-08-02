extends RefCounted

## Layout guards for the bag panel.
##
## The panel this replaced was pinned to the bottom-left corner of the screen by
## hand-tuned offsets in main.tscn — `offset_top = -178.0` for the backpack, a raw
## `offset_left = 594.0` for a chest, both measured against a window size the project
## stopped using. That corner is where mobile_controls.gd parks the virtual joystick,
## so on a phone the bag opened underneath the thumbstick, and the cells it opened
## with were the scene's flat 64px whatever the device's viewport actually was.
##
## None of that fails to parse, fails to lint or fails to open. These tests are the
## thing that would have caught it.

var _T

const GRID_SCENE := "res://inventory/inventory.tscn"
const SLOT_SCENE := "res://inventory/inventory_slot.tscn"
const INTERFACE_SCRIPT := "res://ui/inventory_interface.gd"

## The four NewInventory instances main.tscn gives the panel, in scene order. Only
## the backpack starts visible; a chest's grid is shown by set_external_inventory().
const GRID_NAMES := ["PlayerInventory", "EquipInventory", "EquipSwordInventory", "ExternalInventory"]


## Rebuilds the slice of main.tscn the panel needs to run: Main > UI2 >
## InventoryInterface with its five children, plus the InputManager the script
## reaches for at "../../InputManager". inventory_interface.gd has no scene of its
## own — it is a bare Control in main.tscn — so the test has to stand one up.
func _build(viewport_size: Vector2i) -> Node:
	var root := Control.new()
	root.name = "Main"

	var input_manager := InputManager.new()
	input_manager.name = "InputManager"
	root.add_child(input_manager)

	var layer := CanvasLayer.new()
	layer.name = "UI2"
	root.add_child(layer)

	# Untyped: the script declares no class_name, so a `Control`-typed variable would
	# refuse to compile every call into it below.
	var interface = Control.new()
	interface.name = "InventoryInterface"
	interface.set_script(load(INTERFACE_SCRIPT))
	interface.visible = false

	var grid_scene: PackedScene = load(GRID_SCENE)
	for grid_name in GRID_NAMES:
		var grid: Control = grid_scene.instantiate()
		grid.name = grid_name
		grid.visible = grid_name == "PlayerInventory"
		# Before the interface enters the tree, so its @onready vars resolve.
		interface.add_child(grid)

	var slot_scene: PackedScene = load(SLOT_SCENE)
	var grabbed: Control = slot_scene.instantiate()
	grabbed.name = "GrabbedSlot"
	grabbed.visible = false
	interface.add_child(grabbed)

	layer.add_child(interface)

	await _T.instantiate_ui(root, viewport_size)
	return root


## Opens the panel and lets the container sort settle.
func _open(root: Node) -> Node:
	var interface = root.get_node("UI2/InventoryInterface")
	interface.visible = true
	await root.get_tree().process_frame
	await root.get_tree().process_frame
	return interface


func test_the_bag_opens_centred_not_in_the_joysticks_corner() -> String:
	var viewport_size := Vector2i(1280, 720)
	var root: Node = await _build(viewport_size)
	var interface = await _open(root)

	var frame: Control = interface._panel_frame.get_node("Center/Frame")
	var rect := frame.get_global_rect()
	var frame_centre := rect.position + rect.size * 0.5
	var screen_centre := Vector2(viewport_size) * 0.5

	# mobile_controls.gd puts the joystick at (margin, height - margin - stick), i.e.
	# hard against the bottom-left corner. A point 80px in from that corner stands for
	# the whole thumb zone.
	var thumb := Vector2(80.0, float(viewport_size.y) - 80.0)

	var err: String = _T.assert_true(frame_centre.distance_to(screen_centre) < 2.0,
		"the bag's frame centre %s sits on the screen centre %s" % [frame_centre, screen_centre])
	if err == "":
		err = _T.assert_false(rect.has_point(thumb),
			"the bag %s stays out of the joystick's corner %s" % [rect, thumb])

	_T.free_ui(root)
	return err


func test_the_grids_are_laid_out_by_the_frame_not_by_the_scenes_offsets() -> String:
	var root: Node = await _build(Vector2i(1280, 720))
	var interface = await _open(root)

	# Reparented into the frame's column, so the absolute offsets main.tscn still
	# carries on these instances no longer decide anything.
	var backpack: Node = interface.player_inventory
	var chest: Node = interface.external_inventory
	var err: String = _T.assert_true(
		backpack.get_parent() == interface._column and chest.get_parent() == interface._column,
		"both grids hang off the frame's column, not off the panel root")

	if err == "":
		# The dragged stack has to draw over the panel it was lifted out of, and a
		# CanvasItem's later siblings paint on top.
		var last: Node = interface.get_child(interface.get_child_count() - 1)
		err = _T.assert_true(last == interface.grabbed_slot,
			"GrabbedSlot is the last child of the panel root, so it draws over the frame")

	_T.free_ui(root)
	return err


func test_slot_size_follows_the_viewport_instead_of_the_scenes_64px() -> String:
	var small: float = await _first_slot_edge(Vector2i(480, 800))
	var large: float = await _first_slot_edge(Vector2i(1920, 1080))

	# A phone must never drop under the touch floor...
	var err: String = _T.assert_gte(small, UiTheme.TOUCH_MIN,
		"a 480x800 phone gets slots at least %s px across (got %s)" % [UiTheme.TOUCH_MIN, small])
	if err != "":
		return err

	# ...and a desktop window must not be stuck on the phone's size. Both halves
	# together are what a revert to the scene's flat 64 would fail.
	err = _T.assert_gt(large, small,
		"a 1920x1080 window gets larger slots (%s) than a phone (%s)" % [large, small])
	if err != "":
		return err
	return _T.assert_gt(large, NewSlot.BASE_SIZE,
		"a 1920x1080 window scales past the scene's authored %s px cell (got %s)"
			% [NewSlot.BASE_SIZE, large])


## Builds a panel at `viewport_size`, fills the backpack, and reports the edge its
## first cell was drawn at. custom_minimum_size rather than `size`, so the assertion
## does not depend on how many frames the container sort has had.
func _first_slot_edge(viewport_size: Vector2i) -> float:
	var root: Node = await _build(viewport_size)
	var interface = root.get_node("UI2/InventoryInterface")

	var data := InventoryData.new()
	for _i in 12:
		data.inventory_slot_datas.append(null)
	interface.set_player_inventory_data(data)

	await _open(root)

	var grid: GridContainer = interface.player_inventory.item_grid
	var edge := 0.0
	if grid.get_child_count() > 0:
		var slot: Control = grid.get_child(0)
		edge = slot.custom_minimum_size.x

	_T.free_ui(root)
	return edge


func test_the_panel_has_a_close_button_wired_to_the_managers_handshake() -> String:
	var root: Node = await _build(Vector2i(1280, 720))
	var interface = await _open(root)

	# The bug this guards: the bag had no close affordance at all, so on a phone the
	# only way out was the same BAG button that opened it.
	var button := interface._panel_frame.find_child("CloseButton", true, false) as Button
	if button == null:
		_T.free_ui(root)
		return "the bag panel has no CloseButton; there is no way out of it on a phone"

	# force_close, not a local hide: NewInventoryManager is what re-enables input,
	# restores the mouse mode and brings the hotbar back.
	var asked := [false]
	interface.force_close.connect(func(): asked[0] = true)
	button.pressed.emit()

	var err: String = _T.assert_true(asked[0],
		"pressing X asks NewInventoryManager to close the bag")
	_T.free_ui(root)
	return err
