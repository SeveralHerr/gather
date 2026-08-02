extends Control

## The bag: the player's own inventory grid, the open container's grid when a chest
## is showing, and the stack the player is currently dragging between the two.
##
## ## Why the layout is built here and not in main.tscn
##
## The scene pinned PlayerInventory to the bottom-left corner with hand-tuned
## offsets (`anchor_bottom = 1.0`, `offset_top = -178.0`) and ExternalInventory at a
## raw `offset_left = 594.0` — a pixel column measured against the old 1152x648
## window, the exact class of bug gather-6fx went through the rest of the UI to
## remove. That cost two things. Every grid drifted toward the middle of the screen
## as the window grew, and the bottom-left corner the bag sat in is precisely where
## mobile_controls.gd parks the virtual joystick, so on a phone the bag opened
## underneath the thumbstick.
##
## _ready() therefore reparents the grids into a PanelFrame and lets that centre
## them, overriding whatever offsets the scene still carries — the same reason
## skill_tree_ui.gd, land_purchase_ui.gd and mobile_controls.gd lay themselves out in
## code. Nothing below reads a viewport dimension to compute a *position*: positions
## come from the frame's CenterContainer, sizes from UiTheme.
##
## Draw order is the other half of the joystick bug and cannot be fixed from here. A
## CanvasLayer paints its children in tree order, so whether MobileControls covers
## this panel is settled by the node order under UI2 in main.tscn.
##
## ## Who owns open and closed
##
## NewInventoryManager still does: it flips this Control's `visible` and performs the
## disable_input / mouse-mode / hotbar handshake around it. The frame only follows
## that, and every way out of the panel — the X, Escape, a click on the backdrop,
## walking away from a chest — routes back out through `force_close` so the handshake
## always runs. Hiding the frame directly from in here would leave the player frozen
## with an empty screen.

signal drop_slot_data(slot_data: SlotData)
signal force_close

const TITLE_BAG := "INVENTORY"
## Fallback heading for a container that does not name itself.
const TITLE_CONTAINER := "CHEST"

## How far the dragged stack trails the mouse cursor, before scaling.
const CURSOR_TRAIL := 5.0

var grabbed_slot_data: SlotData
var external_inventory_owner

@onready var player_inventory: NewInventory = $PlayerInventory
@onready var grabbed_slot: NewSlot  = $GrabbedSlot
@onready var external_inventory: NewInventory = $ExternalInventory
@onready var equip_inventory = $EquipInventory
@onready var equip_sword_inventory = $EquipSwordInventory
@onready var input_manager: InputManager = $"../../InputManager"

## The chrome — backdrop, centred frame, title bar, close button — and the column the
## grids are reparented into.
var _panel_frame: PanelFrame
var _column: VBoxContainer
var _external_heading: Label
var _player_heading: Label

## The finger currently on the screen, and where it is. -1 means "no touch": the
## dragged stack then follows the mouse, which under emulate_mouse_from_touch is
## still parked wherever the last finger left it.
var _touch_index := -1
var _touch_position := Vector2.ZERO

## Scaled pixel offsets, recomputed on every resize so _physics_process never has to.
var _cursor_trail := CURSOR_TRAIL
var _touch_lift := float(UiTheme.GAP)


func _ready():
	# The root only hosts the frame and the dragged stack; it must never swallow a
	# click aimed at the world. The frame's own backdrop is what stops clicks, and
	# only while the panel is open.
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)

	_build_frame()

	# The dragged stack is a decoration that chases the pointer across the whole
	# panel. Left hit-testable it would eat the click meant for the slot underneath
	# it, which is exactly the click that puts the stack down.
	_make_click_through(grabbed_slot)

	visibility_changed.connect(_on_visibility_changed)
	set_process_input(visible)

	var vp := get_viewport()
	if vp != null and not vp.size_changed.is_connected(_apply_scale):
		vp.size_changed.connect(_apply_scale)
	_apply_scale()


# --- construction ------------------------------------------------------------

func _build_frame() -> void:
	_panel_frame = PanelFrame.new()
	_panel_frame.setup(TITLE_BAG)
	_panel_frame.close_requested.connect(_on_close_requested)
	add_child(_panel_frame)
	# A CanvasItem's later siblings draw on top, and the dragged stack has to float
	# over the panel it was lifted out of — so the frame goes first and GrabbedSlot
	# stays the last child of this root.
	move_child(_panel_frame, 0)

	# Right-click on empty space still throws a single item on the ground, the gesture
	# this panel has always had. PanelFrame's own backdrop handler owns the left button
	# (close), so the two share the node rather than fight over it: a left click that
	# closes the panel still drops the whole held stack on the way out, through
	# _on_visibility_changed below.
	var backdrop := _panel_frame.get_node_or_null("Backdrop") as Control
	if backdrop != null:
		backdrop.gui_input.connect(_on_backdrop_input)
	else:
		push_error("InventoryInterface: PanelFrame has no Backdrop; right-click-to-drop is dead")

	_column = VBoxContainer.new()
	_column.name = "Inventories"
	_panel_frame.content.add_child(_column)

	# Container first, backpack under it — the direction items move when you empty a
	# chest, and the order every game that has this screen uses.
	_external_heading = _build_heading("CONTAINER")
	_column.add_child(_external_heading)
	_adopt(external_inventory)

	_player_heading = _build_heading("BACKPACK")
	_column.add_child(_player_heading)
	_adopt(player_inventory)

	# Neither equip grid is wired to anything yet: both are `visible = false` in
	# main.tscn and no code ever shows them. They come along so this root is left
	# holding exactly the frame and the dragged stack, and so they inherit the frame's
	# layout for free if they are ever finished.
	_adopt(equip_inventory)
	_adopt(equip_sword_inventory)

	_external_heading.visible = external_inventory.visible


## Moves a grid out of the scene's absolute-offset layout and into the frame's
## column, where the container decides its position. Shrink-centred rather than
## filled so a three-slot chest sits under the middle of a six-slot backpack instead
## of hugging the left edge of a panel sized for the wider one.
func _adopt(node: Node) -> void:
	if node == null:
		return

	var control := node as Control
	if control != null:
		control.size_flags_horizontal = Control.SIZE_SHRINK_CENTER

	var previous := node.get_parent()
	if previous != null:
		previous.remove_child(node)
	_column.add_child(node)


func _build_heading(text: String) -> Label:
	var label := Label.new()
	label.name = text.capitalize() + "Heading"
	label.text = text
	label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	label.add_theme_color_override("font_color", UiTheme.COLOR_TEXT_DIM)
	return label


## Makes a whole subtree invisible to the mouse. One call is not enough: Container
## defaults to MOUSE_FILTER_PASS, so a slot's MarginContainer would still be picked
## as the topmost control under the cursor and the click would stop at a node with
## nothing listening rather than reaching the slot behind it.
func _make_click_through(node: Node) -> void:
	if node == null:
		return
	var control := node as Control
	if control != null:
		control.mouse_filter = Control.MOUSE_FILTER_IGNORE
	for child in node.get_children():
		_make_click_through(child)


# --- layout ------------------------------------------------------------------

## Re-derives every size from the live viewport. Runs once at _ready and again on
## every window resize, because the project's stretch mode is "disabled" and so
## nothing here scales on its own.
func _apply_scale() -> void:
	if _panel_frame == null or not is_inside_tree():
		return
	var vp := get_viewport()
	if vp == null:
		return
	var vp_size := vp.get_visible_rect().size
	if vp_size.x <= 0.0 or vp_size.y <= 0.0:
		return

	# One edge for every cell on screen, floored at UiTheme.TOUCH_MIN. This is the
	# whole "the UI is too small on a phone" fix: the scene's flat 64px is barely half
	# a fingertip on a device whose viewport reports its real pixels.
	var side := UiTheme.scaled_touch(NewSlot.BASE_SIZE, vp_size)
	player_inventory.apply_slot_size(side)
	external_inventory.apply_slot_size(side)
	if equip_inventory is NewInventory:
		equip_inventory.apply_slot_size(side)
	if equip_sword_inventory is NewInventory:
		equip_sword_inventory.apply_slot_size(side)

	# Not in a container — a direct child of this root — so custom_minimum_size alone
	# would not resize it.
	grabbed_slot.apply_metrics(side)
	grabbed_slot.size = Vector2(side, side)

	_column.add_theme_constant_override(
		"separation", int(round(UiTheme.scaled(UiTheme.GAP, vp_size))))

	var heading_font := UiTheme.scaled_font(UiTheme.FONT_SMALL, vp_size)
	_external_heading.add_theme_font_size_override("font_size", heading_font)
	_player_heading.add_theme_font_size_override("font_size", heading_font)

	_cursor_trail = UiTheme.scaled(CURSOR_TRAIL, vp_size)
	_touch_lift = UiTheme.scaled(UiTheme.GAP, vp_size)


# --- pointer -----------------------------------------------------------------

func _input(event: InputEvent) -> void:
	# Tracked so the dragged stack follows the finger itself rather than the cursor
	# that emulate_mouse_from_touch happens to drag along behind it. Nothing is
	# consumed here; the slots' own gui_input still decides every pick-up and drop.
	var touch := event as InputEventScreenTouch
	if touch != null:
		if touch.pressed:
			_touch_index = touch.index
			_touch_position = touch.position
		elif touch.index == _touch_index:
			_touch_index = -1
		return

	var drag := event as InputEventScreenDrag
	if drag != null and drag.index == _touch_index:
		_touch_position = drag.position


## Where the dragged stack is drawn. Under a mouse it trails down-right of the
## cursor, the way it always has. Under a finger that would put it beneath the thumb
## — the one part of the screen the player cannot see — so a live touch draws it just
## above the contact point instead. Cosmetic either way: which slot the stack lands
## in is decided by that slot's own gui_input, never by this position.
func _grabbed_slot_position() -> Vector2:
	if _touch_index != -1:
		return _touch_position - Vector2(grabbed_slot.size.x * 0.5, grabbed_slot.size.y + _touch_lift)
	return get_global_mouse_position() + Vector2(_cursor_trail, _cursor_trail)


func _physics_process(_delta):
	if grabbed_slot.visible:
		grabbed_slot.global_position = _grabbed_slot_position()

	# Walking away from a chest closes the bag. Load-bearing: the container's
	# InventoryData stays connected to on_inventory_interact until
	# clear_external_inventory() runs, so a panel left open across the map would keep
	# a remote chest live and writable.
	if external_inventory_owner \
			and external_inventory_owner.global_position.distance_to(PlayerManager.get_global_position()) > 15:
		force_close.emit()


# --- open / close ------------------------------------------------------------

func _on_visibility_changed():
	# The frame follows this Control rather than owning its own open state, so the
	# chrome cannot drift out of step with NewInventoryManager's handshake.
	if _panel_frame != null:
		if visible:
			_panel_frame.open()
		else:
			_panel_frame.close()

	set_process_input(visible)
	if not visible:
		# A finger still logically down when the panel goes away would leave the stack
		# pinned to a stale coordinate the next time one is picked up.
		_touch_index = -1

	if not visible and grabbed_slot_data:
		drop_slot_data.emit(grabbed_slot_data)
		grabbed_slot_data = null
		update_grabbed_slot()


## The X, Escape and a click on the backdrop all arrive here. They are routed back to
## NewInventoryManager through `force_close` rather than hiding the frame, because it
## is the manager that hands input back to the player, restores the mouse mode and
## brings the hotbar back.
func _on_close_requested() -> void:
	if not visible:
		return
	force_close.emit()


func _on_backdrop_input(event: InputEvent):
	# Right button only, and only while something is held. The left button belongs to
	# PanelFrame's backdrop-to-close, and a left click while holding a stack still
	# drops the whole thing — _on_visibility_changed does it on the way out.
	if grabbed_slot_data == null:
		return

	var mouse := event as InputEventMouseButton
	if mouse == null or not mouse.pressed or mouse.button_index != MOUSE_BUTTON_RIGHT:
		return

	drop_slot_data.emit(grabbed_slot_data.create_single_slot_data())
	if grabbed_slot_data.count < 1:
		grabbed_slot_data = null

	update_grabbed_slot()


# --- inventory ---------------------------------------------------------------

func set_player_inventory_data(inventory_data: InventoryData) -> void:
	inventory_data.inventory_interact.connect(on_inventory_interact)
	player_inventory.set_inventory_data(inventory_data)

func on_inventory_interact(inventory_data: InventoryData, index: int, button: int ):
	match [grabbed_slot_data, button]:
		[null, MOUSE_BUTTON_LEFT]:
			grabbed_slot_data = inventory_data.grab_slot_data(index)
		# Something is in the slot data
		[_, MOUSE_BUTTON_LEFT]:
			grabbed_slot_data = inventory_data.drop_slot_data(grabbed_slot_data, index)

		[null, MOUSE_BUTTON_RIGHT]:
			inventory_data.use_slot_data(index)
		# Something is in the slot data
		[_, MOUSE_BUTTON_RIGHT]:
			grabbed_slot_data = inventory_data.drop_single_slot_data(grabbed_slot_data, index)

	update_grabbed_slot()

func update_grabbed_slot() -> void:
	if grabbed_slot_data:
		grabbed_slot.show()
		grabbed_slot.set_slot_data(grabbed_slot_data)
	else:
		grabbed_slot.hide()


func set_external_inventory(_external_inventory_owner):
	external_inventory_owner = _external_inventory_owner
	var inventory_data = external_inventory_owner.inventory_data

	inventory_data.inventory_interact.connect(on_inventory_interact)
	external_inventory.set_inventory_data(inventory_data)

	external_inventory.show()
	if _external_heading != null:
		_external_heading.show()
	if _panel_frame != null:
		_panel_frame.set_title(_container_title(external_inventory_owner))

	# Load-bearing: the player must not swing a pickaxe at the chest they are looking
	# into. NewInventoryManager sets the same flag from the panel's visibility; this
	# is the half that covers a container opened while the bag is already up.
	input_manager.disable_input = true

func clear_external_inventory():
	if not external_inventory_owner:
		return

	var inventory_data = external_inventory_owner.inventory_data

	inventory_data.inventory_interact.disconnect(on_inventory_interact)
	external_inventory.clear_inventory_data(inventory_data)

	external_inventory.hide()
	if _external_heading != null:
		_external_heading.hide()
	if _panel_frame != null:
		_panel_frame.set_title(TITLE_BAG)

	external_inventory_owner = null
	input_manager.disable_input = false


## What to call the open container in the title bar. Object.get() answers null for a
## property the owner does not declare, so a chest that never gained a display name
## costs one fallback rather than a hard requirement on every future container.
func _container_title(owner_node) -> String:
	if owner_node == null:
		return TITLE_CONTAINER
	var label: Variant = owner_node.get("display_name")
	if label is String and label != "":
		var text: String = label
		return text.to_upper()
	return TITLE_CONTAINER
