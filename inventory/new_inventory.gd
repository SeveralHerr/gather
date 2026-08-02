extends PanelContainer
class_name NewInventory

## One grid of inventory slots: the player's backpack, or an open chest's contents.
## Three of these live under UI/InventoryInterface, which decides where they sit and
## how big they are.
##
## Nothing here picks a pixel size. The owner derives one slot edge from the live
## viewport through UiTheme.scaled_touch() and pushes it in with apply_slot_size(),
## so a phone gets finger-sized cells and a 4K window gets proportionally larger ones
## from the same code — see the sizing note in ui/ui_theme.gd for why a fixed number
## cannot work with window/stretch/mode "disabled".

const INVENTORY_SLOT = preload("res://inventory/inventory_slot.tscn")

## Slot edge in real pixels. Held as a field rather than passed through
## populate_item_grid(), because the grid is rebuilt from scratch on every inventory
## change and slots built by a later rebuild have to match the first batch.
var slot_size := 0.0

@onready var item_grid: GridContainer = $MarginContainer/ItemGrid
@onready var _margin: MarginContainer = $MarginContainer


func _ready() -> void:
	# A recessed well behind the cells, so the grid reads as part of the panel frame
	# around it rather than as a floating default-themed box. Applied here rather than
	# in inventory.tscn so all three instances (backpack, chest, the two unfinished
	# equip slots) share one source.
	add_theme_stylebox_override("panel", UiTheme.inset_style())


## Sets the edge every cell in this grid is drawn at, now and for every cell built
## from here on, and scales the gaps and padding around them to match. Idempotent, so
## the owner can re-apply it on every viewport resize.
func apply_slot_size(side: float) -> void:
	if side <= 0.0:
		return
	slot_size = side

	var factor := UiTheme.scale_for_node(self)
	var gap := int(round(UiTheme.GAP * factor * 0.5))
	item_grid.add_theme_constant_override("h_separation", gap)
	item_grid.add_theme_constant_override("v_separation", gap)

	var pad := int(round(UiTheme.GAP * factor))
	_margin.add_theme_constant_override("margin_left", pad)
	_margin.add_theme_constant_override("margin_top", pad)
	_margin.add_theme_constant_override("margin_right", pad)
	_margin.add_theme_constant_override("margin_bottom", pad)

	for child in item_grid.get_children():
		if child is NewSlot:
			child.apply_metrics(side)


func set_inventory_data(inventory_data: InventoryData) -> void:
	inventory_data.inventory_updated.connect(populate_item_grid)
	populate_item_grid(inventory_data)

func clear_inventory_data(inventory_data: InventoryData) -> void:
	inventory_data.inventory_updated.disconnect(populate_item_grid)


func populate_item_grid(inventory_data: InventoryData) -> void:
	for child in item_grid.get_children():
		child.queue_free()

	for slot_data in inventory_data.inventory_slot_datas:
		var slot = INVENTORY_SLOT.instantiate()
		item_grid.add_child(slot)

		# After add_child, so the slot's @onready nodes exist and apply_metrics() can
		# write the padding and label size straight away rather than deferring them.
		if slot_size > 0.0:
			slot.apply_metrics(slot_size)

		slot.slot_clicked.connect(inventory_data.on_slot_clicked)

		if slot_data:
			slot.set_slot_data(slot_data)
