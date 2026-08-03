extends PanelContainer

## The six-slot hotbar: what the player is holding, and the only place the game
## says which of the six that is.
##
## Selection used to be keyboard-only (`_unhandled_key_input` on KEY_1..KEY_6),
## the highlight was a 2px `draw_center = false` border rendered at the scene's
## 0.86 scale, and nothing on screen said the number keys did anything at all. A
## phone player had no affordance at all, short of a keyboard they do not have. (The
## touch overlay briefly carried an ITEM button that cycled forward one slot; it was
## removed in gather-mxf and there is no HOTBAR_SLOT_COUNT there any more.) So there are
## now four ways in, all of them through `select_slot()`:
##
##   * the number keys 1..6, unchanged;
##   * the Left / Right arrow keys and the mouse wheel, which step the row one slot
##     at a time;
##   * a tap or click on a slot;
##   * the < and > buttons flanking the row, which is the affordance that makes
##     the direction of travel visible rather than implied.
##
## The last two only started working on desktop when the cursor stopped being
## captured (player.gd). Before that they were drawn but unclickable, and Q / E
## existed to route around them — E being also the `gather` key, which meant every
## swing of the pickaxe stepped the hotbar. See `_unhandled_key_input`.
##
## Everything it draws is sized from the viewport in `_apply_layout()` rather
## than from the scene, because the project runs with
## `window/stretch/mode = "disabled"`: the viewport is the device's real pixel
## size and nothing scales for free. That includes the node's own rect, which is
## why the fixed offsets and the 0.86 scale main.tscn instances this with are
## overwritten on the first layout pass.

signal hot_bar_use(index: int)
signal hot_bar_stop(index: int)
signal hot_bar_selected(index: int)

const INVENTORY_SLOT = preload("res://inventory/inventory_slot.tscn")

## The hotbar mirrors the first six inventory slots. KEY_1..KEY_6 assume this number.
const SLOT_COUNT := 6

## The two keys that step the selection, as constants rather than literals inside
## `_unhandled_key_input`, so `test_hotbar_selection.gd` can check them against the
## InputMap. Every key this file claims is a *raw keycode* — it deliberately does not
## go through the InputMap — which means nothing stops one of them also being bound
## to a gameplay action, and nothing reports it when one is. That is exactly how E
## ended up being both `gather` and "next slot".
const STEP_PREV_KEY := KEY_LEFT
const STEP_NEXT_KEY := KEY_RIGHT

## Base sizes, pre-scale, in the sense UiTheme means: multiplied by
## `UiTheme.scale_for()` and floored at `UiTheme.TOUCH_MIN` where a finger has to
## land. None of them is ever used as a position.
const SLOT_BASE := 56.0
const PAD_BASE := 4.0
const BOTTOM_MARGIN_BASE := 10.0

## The narrowest an arrow may ever be. An arrow is a whole slot tall and *wants*
## to be `UiTheme.TOUCH_MIN` wide like everything else a finger lands on; it gives
## up width only when the row cannot afford it, and never past this.
##
## Six 48px slots plus two 48px arrows genuinely do not fit across a 390px portrait
## phone — that needs 398px before padding — so something has to give, and the
## slots win: they are what the player is aiming at, they carry the item art, and
## they are the direct route to a slot that the arrows only approximate. The arrows
## therefore come out around 28px in portrait, under the 40x40 tap floor
## `validate-ui` checks, which is a knowing trade rather than an oversight
## (`gather-bb7`). What is *not* a trade is the case this constant used to force
## everywhere: the width was a fixed 0.6 of a slot, so a landscape phone with 470px
## of clear space beside the row still drew 29px arrows. Room is now spent when
## there is room.
const ARROW_WIDTH_MIN := 28.0

## How much of the viewport width the whole row may occupy before the slots start
## shrinking to fit. Below roughly a 340px-wide viewport even this cannot keep
## every slot at TOUCH_MIN, and the row is allowed to overhang rather than shrink
## past the point a thumb can hit it.
const ROW_WIDTH_FRACTION := 0.96

## Unselected slots are dimmed as well as differently framed. The old highlight
## was a border alone and at 0.86 scale you genuinely could not tell which slot
## was live.
const UNSELECTED_MODULATE := Color(1.0, 1.0, 1.0, 0.72)

var selected_index: int = 0
var inv: InventoryData

## The selected slot's frame — `UiTheme.overlay_style(true)`, i.e. the brighter
## gold border, because the hotbar sits directly over the world with no backdrop.
## Initialised here rather than in `_ready()` so `set_inventory_data()` cannot
## race it.
var style: StyleBoxFlat = UiTheme.overlay_style(true)
var unselected_style: StyleBoxFlat = UiTheme.overlay_style(false)

# Resolved live against the inventory instead of cached. Holding the SlotData meant
# that consuming the last item in a slot left the hotbar pointing at a slot the
# inventory had already dropped, so the player kept acting with a tool they no
# longer had and populate_hot_bar dereferenced a slot that could be null.
var selected_slot_data: SlotData:
	get:
		if not inv:
			return null
		if selected_index < 0 or selected_index >= inv.inventory_slot_datas.size():
			return null
		return inv.inventory_slot_datas[selected_index]

@onready var margin_container: MarginContainer = $MarginContainer
@onready var row: HBoxContainer = $MarginContainer/Row
@onready var prev_button: Button = $MarginContainer/Row/PrevButton
@onready var next_button: Button = $MarginContainer/Row/NextButton
@onready var h_box_container: HBoxContainer = $MarginContainer/Row/HBoxContainer
@onready var input_manager: InputManager = $"../../Systems/InputManager"
@onready var held_item_texture: TextureRect = $"../../World/Player/HeldItemTexture"
@onready var tile_map: TileMapHandler = $"../.."


func _ready():
	add_theme_stylebox_override("panel", UiTheme.overlay_style())

	UiTheme.style_button(prev_button)
	UiTheme.style_button(next_button)
	prev_button.pressed.connect(step_selection.bind(-1))
	next_button.pressed.connect(step_selection.bind(1))

	input_manager.gather_input_press.connect(_on_gather)
	input_manager.gather_input_release.connect(_on_gather_stop)

	var vp := get_viewport()
	if vp != null and not vp.size_changed.is_connected(_apply_layout):
		vp.size_changed.connect(_apply_layout)

	# The touch overlay covers the bottom corners of the screen when it is up, so
	# the hotbar has to know when that changes and lift itself clear.
	var mobile := _mobile_controls()
	if mobile != null and not mobile.visibility_changed.is_connected(_apply_layout):
		mobile.visibility_changed.connect(_apply_layout)

	_apply_layout()
	# Again once the whole tree is up: MobileControls is a later sibling in
	# main.tscn, so on the first pass it has not decided whether it is visible yet
	# and _bottom_obstruction() answers for a half-built overlay.
	_apply_layout.call_deferred()

func _process(_delta):
	if held_item_texture.visible:
		var tile_pos =  tile_map.get_tile_in_front_of_player()
		held_item_texture.global_position = tile_pos

		# Same is_wall the placement itself will pass, or the tint lies: walls are the one
		# placeable allowed onto a floor, so asking with is_wall=false paints a legal
		# placement red.
		var as_wall: bool = selected_slot_data != null and selected_slot_data.item is GameItemWall2
		if tile_map.is_occupied(tile_map.tileMap.local_to_map(tile_pos), true, as_wall):
			held_item_texture.modulate = Color(1, 0, 0, 140)
		else:
			held_item_texture.modulate = Color(1, 1, 1, 1)

func _unhandled_key_input(event):
	if not visible or not event.is_pressed():
		return

	if range(int(KEY_1), int(KEY_1) + SLOT_COUNT).has(event.keycode):
		select_slot(event.keycode - KEY_1)
		return

	# The arrow keys, and deliberately NOT Q / E.
	#
	# E is `gather`. Nothing in the gather path marks the event handled, so it fell
	# through to here and stepped the selection as well — every single swing of the
	# pickaxe silently advanced the hotbar by one slot. That is why this pair is gone
	# rather than merely rebound: the collision was invisible in the binding table,
	# because `gather` is an InputMap action and this was a raw keycode, and the two
	# never appear in the same place.
	#
	# Left / Right are raw keycodes for the same reason the number keys above are:
	# they are hotbar selection, not an engine-level UI action, and going through
	# ui_left / ui_right would hand them to Control focus navigation first.
	if event.keycode == STEP_PREV_KEY:
		step_selection(-1)
	elif event.keycode == STEP_NEXT_KEY:
		step_selection(1)

func _unhandled_input(event):
	# The wheel is the other affordance a captured cursor leaves working, and it
	# is what a Forager player reaches for first. Nothing else in the game binds
	# it.
	if not visible:
		return
	var mouse := event as InputEventMouseButton
	if mouse == null or not mouse.pressed:
		return
	if mouse.button_index == MOUSE_BUTTON_WHEEL_DOWN:
		step_selection(1)
		get_viewport().set_input_as_handled()
	elif mouse.button_index == MOUSE_BUTTON_WHEEL_UP:
		step_selection(-1)
		get_viewport().set_input_as_handled()

func _on_gather():
	hot_bar_use.emit(selected_index)

func _on_gather_stop():
	hot_bar_stop.emit(selected_index)


## The one way the selection ever changes. The number keys, Q/E, the wheel, a tap
## on a slot and the two arrow buttons all land here, so the five paths cannot
## drift apart — which is exactly what happened when MobileControls had to
## synthesise a keypress to reach the only implementation there was.
func select_slot(index: int) -> void:
	if index < 0 or index >= SLOT_COUNT:
		return

	selected_index = index
	_apply_selection()
	update_placed_slot()
	hot_bar_selected.emit(selected_index)


## Moves the selection by `delta` slots, wrapping. `posmod` rather than `%` so
## stepping back off slot 1 lands on slot 6 instead of -1 — the direction the retired
## ITEM button could never go.
func step_selection(delta: int) -> void:
	select_slot(posmod(selected_index + delta, SLOT_COUNT))


## A tap or a click on a slot selects it.
##
## This used to forward straight to `InventoryData.on_slot_clicked`, i.e. to the
## inventory's grab/drop handler. That could never do anything useful from here:
## the hotbar is hidden whenever the inventory interface is open
## (new_inventory_manager.gd) and the grabbed slot only draws inside that
## interface, so a click on a *visible* hotbar slot pulled the stack into an
## invisible hand. Selecting is what a hotbar click means everywhere else, and on
## a phone it is the only direct way to reach slot 4 without cycling past 2 and 3.
func _on_slot_clicked(index: int, _button: int) -> void:
	select_slot(index)

func set_inventory_data(inventory_data: InventoryData) -> void:
	inv = inventory_data

	inventory_data.inventory_updated.connect(populate_hot_bar)
	populate_hot_bar(inventory_data)
	hot_bar_use.connect(inventory_data.use_slot_data)
	hot_bar_stop.connect(inventory_data.stop_slot_data)
	hot_bar_selected.connect(inventory_data.show_slot_data)
	hot_bar_selected.connect(_on_select)

func _on_select(_i):
	update_placed_slot()
	pass

func populate_hot_bar(inventory_data: InventoryData) -> void:
	var selected := selected_slot_data
	if not selected or selected.count <= 0:
		held_item_texture.texture = null

	for child in h_box_container.get_children():
		# Detached as well as freed: queue_free() leaves the node a child until the
		# end of the frame, and _apply_layout() below asks the container for its
		# minimum size in this one.
		h_box_container.remove_child(child)
		child.queue_free()

	var hot_bar_slots = inventory_data.inventory_slot_datas.slice(0, SLOT_COUNT)
	for index in hot_bar_slots.size():
		var slot_data = hot_bar_slots[index]
		var slot = INVENTORY_SLOT.instantiate()
		h_box_container.add_child(slot)

		# The number is a child of the slot, not of the row, so it does not shift
		# the index slot_clicked reports.
		slot.add_child(_build_number_label(index))

		slot.slot_clicked.connect(_on_slot_clicked)

		if slot_data:
			slot.set_slot_data(slot_data)

	# Both of these have to run after the rebuild: the highlight lives on the slot
	# nodes, which have just been replaced, and the row's width depends on how many
	# of them there are.
	_apply_selection()
	_apply_layout()


## The 1..6 label that makes the number-key binding discoverable. Size flags put
## it in the slot's top-left corner: PanelContainer honours them through
## `fit_child_in_rect`, which is the same mechanism that parks the slot scene's
## own QuantityLabel in the top-right.
func _build_number_label(index: int) -> Label:
	var label := Label.new()
	label.name = "HotbarNumber"
	label.text = str(index + 1)
	label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	label.size_flags_horizontal = Control.SIZE_SHRINK_BEGIN
	label.size_flags_vertical = Control.SIZE_SHRINK_BEGIN
	label.add_theme_color_override("font_color", UiTheme.COLOR_TEXT_DIM)
	label.add_theme_color_override("font_outline_color", Color(0, 0, 0, 1))
	label.add_theme_constant_override("outline_size", 3)
	return label


## Repaints the six slots for the current `selected_index`. Keyed by index rather
## than by SlotData, so the highlight stays put when the slot is emptied.
func _apply_selection() -> void:
	for index in h_box_container.get_child_count():
		var slot := h_box_container.get_child(index) as Control
		if slot == null:
			continue

		var chosen := index == selected_index
		slot.add_theme_stylebox_override("panel", style if chosen else unselected_style)
		slot.modulate = Color.WHITE if chosen else UNSELECTED_MODULATE

		var number := slot.get_node_or_null("HotbarNumber") as Label
		if number != null:
			number.add_theme_color_override(
				"font_color", UiTheme.COLOR_GOLD if chosen else UiTheme.COLOR_TEXT_DIM)


## The four lengths the row is built out of, for a viewport, as
## `{"slot", "arrow", "pad", "gap"}`.
##
## The row is SLOT_COUNT slots plus two arrows, separated by SLOT_COUNT + 1 gaps,
## inside the panel's padding. That budget is spent in **priority order** rather than
## split by a fixed ratio, because the two are not equally important: the slots are
## what the player aims at, and an arrow is a convenience over a tap on the slot
## itself.
##
##   1. the slots take the size the theme asked for, floored at TOUCH_MIN;
##   2. the arrows take half of whatever is left, up to TOUCH_MIN — so a landscape
##      phone, a tablet or a desktop window, all of which have width to spare, get a
##      full-sized target instead of the 29px sliver a fixed 0.6-of-a-slot ratio used
##      to hand them everywhere (`gather-bb7`);
##   3. only when that leaves less than ARROW_WIDTH_MIN do the slots start giving way
##      in turn, and never below TOUCH_MIN — under roughly a 340px viewport the row
##      overhangs instead, which is the documented last resort.
##
## Static and pure — the viewport is the only input — because the node it belongs to
## cannot be instantiated on its own: `input_manager`, `held_item_texture` and
## `tile_map` are all `@onready` reaches up into main.tscn, so a test that wants to
## know what this row does at 390px would otherwise have to boot the whole game. The
## same reasoning made `MobileControls.resolve_primary()` static.
static func solve_metrics(viewport_size: Vector2) -> Dictionary:
	var pad := UiTheme.scaled(PAD_BASE, viewport_size)
	var gap := UiTheme.scaled(UiTheme.GAP, viewport_size) * 0.5

	var budget := viewport_size.x * ROW_WIDTH_FRACTION - 2.0 * pad \
		- float(SLOT_COUNT + 1) * gap
	var side := UiTheme.scaled_touch(SLOT_BASE, viewport_size)
	var arrow := clampf(
		(budget - float(SLOT_COUNT) * side) * 0.5, ARROW_WIDTH_MIN, UiTheme.TOUCH_MIN)
	side = maxf(UiTheme.TOUCH_MIN, minf(side, (budget - 2.0 * arrow) / float(SLOT_COUNT)))

	return {"slot": side, "arrow": arrow, "pad": pad, "gap": gap}


## Re-derives every size, and the node's own rect, from the current viewport.
##
## main.tscn instances this scene with a hand-tuned offset rect and
## `scale = 0.86`, neither of which adapts to anything; both are overwritten here.
## The rect is set from anchors — bottom centre, growing up and out — so no
## viewport dimension is ever used as a position.
func _apply_layout() -> void:
	if not is_inside_tree() or h_box_container == null:
		return

	var vp := get_viewport_rect().size
	if vp.x <= 0.0 or vp.y <= 0.0:
		return

	var metrics := solve_metrics(vp)
	var pad: float = metrics["pad"]
	var gap: float = metrics["gap"]
	var side: float = metrics["slot"]
	var arrow: float = metrics["arrow"]

	scale = Vector2.ONE

	var pad_px := int(round(pad))
	margin_container.add_theme_constant_override("margin_left", pad_px)
	margin_container.add_theme_constant_override("margin_top", pad_px)
	margin_container.add_theme_constant_override("margin_right", pad_px)
	margin_container.add_theme_constant_override("margin_bottom", pad_px)

	var gap_px := int(round(gap))
	row.add_theme_constant_override("separation", gap_px)
	h_box_container.add_theme_constant_override("separation", gap_px)

	var number_font := UiTheme.scaled_font(UiTheme.FONT_SMALL, vp)
	for child in h_box_container.get_children():
		var slot := child as NewSlot
		if slot == null:
			continue
		# Pushed into the instance, never written back into inventory_slot.tscn: the
		# same scene backs the bag grid and a chest's grid, and apply_metrics() is the
		# owner-facing API slot.gd documents for exactly this. It scales the icon
		# padding and the count text along with the cell.
		slot.apply_metrics(side)
		var number := slot.get_node_or_null("HotbarNumber") as Label
		if number != null:
			number.add_theme_font_size_override("font_size", number_font)

	var arrow_font := UiTheme.scaled_font(UiTheme.FONT_TITLE, vp)
	var arrows: Array[Button] = [prev_button, next_button]
	for button in arrows:
		button.custom_minimum_size = Vector2(arrow, side)
		button.add_theme_font_size_override("font_size", arrow_font)

	# What the row works out to, floored by what the children actually demand —
	# the slot scene belongs to the inventory too and may carry a larger minimum
	# than the arithmetic above assumes.
	var wanted := Vector2(
		2.0 * pad + 2.0 * arrow + float(SLOT_COUNT) * side + float(SLOT_COUNT + 1) * gap,
		2.0 * pad + side)
	var minimum := get_combined_minimum_size()
	var panel := Vector2(maxf(wanted.x, minimum.x), maxf(wanted.y, minimum.y))

	# The row is centred, so it owns the middle `panel.x` of the bottom edge and
	# nothing else. Asking the overlay about that span rather than about the whole
	# width is what keeps the hotbar on the bottom edge in landscape, where the
	# joystick is tall but nowhere near the centre. See `_bottom_obstruction`.
	var half := panel.x * 0.5
	var centre := vp.x * 0.5
	var bottom := UiTheme.scaled(BOTTOM_MARGIN_BASE, vp) \
		+ _bottom_obstruction(centre - half, centre + half)

	grow_horizontal = Control.GROW_DIRECTION_BOTH
	grow_vertical = Control.GROW_DIRECTION_BEGIN
	anchor_left = 0.5
	anchor_right = 0.5
	anchor_top = 1.0
	anchor_bottom = 1.0
	offset_left = -panel.x * 0.5
	offset_right = panel.x * 0.5
	offset_bottom = -bottom
	offset_top = -bottom - panel.y


## How much of the bottom of the screen the touch overlay is covering *under this
## row*, so it sits above the joystick and the thumb cluster instead of underneath
## them. On a portrait phone the two of them own both bottom corners and the hotbar
## is very nearly screen-wide, so there is no bottom-centre gap to sit in and this
## lifts the whole row clear.
##
## In landscape there is such a gap, and the span is what finds it. The overlay used
## to be asked a question with no `x` in it at all and answered with the tallest
## thing it drew anywhere — the joystick, hard against the left edge — which on a
## 844x390 phone parked the hotbar 45% of the way up an empty screen. Zero on
## desktop, where the overlay hides itself.
func _bottom_obstruction(x_min: float, x_max: float) -> float:
	var mobile := _mobile_controls()
	if mobile == null:
		return 0.0
	return mobile.get_bottom_obstruction_height(x_min, x_max)


## The touch overlay, or null on a build that has none. Typed as MobileControls so
## the call above is checked at parse time rather than being a duck-typed guess.
func _mobile_controls() -> MobileControls:
	var parent := get_parent()
	if parent == null:
		return null
	return parent.get_node_or_null("MobileControls") as MobileControls

func update_placed_slot() -> void:
	if held_item_texture and  selected_slot_data and selected_slot_data.item and selected_slot_data.item.is_placeable:
		held_item_texture.show()
		held_item_texture.texture = selected_slot_data.item.get_atlas()
	else:
		held_item_texture.hide()
