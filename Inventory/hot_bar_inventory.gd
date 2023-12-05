extends PanelContainer

signal hot_bar_use(index: int)

const INVENTORY_SLOT = preload("res://Inventory/InventorySlot.tscn")

@onready var h_box_container: HBoxContainer = $MarginContainer/HBoxContainer

func _unhandled_key_input(event):
	if not visible or not event.is_pressed():
		return
	
	if range(KEY_1, KEY_7).has(event.keycode):
		hot_bar_use.emit(event.keycode - KEY_1)

func set_inventory_data(inventory_data: InventoryData) -> void:
	inventory_data.inventory_updated.connect(populate_hot_bar)
	populate_hot_bar(inventory_data)
	hot_bar_use.connect(inventory_data.use_slot_data)

func populate_hot_bar(inventory_data: InventoryData) -> void:
	for child in h_box_container.get_children():
		child.queue_free()
		
	for slot_data in inventory_data.inventory_slot_datas.slice(0, 6):
		var slot = INVENTORY_SLOT.instantiate()
		h_box_container.add_child(slot)
		
		slot.slot_clicked.connect(inventory_data.on_slot_clicked)
		
		if slot_data:
			slot.set_slot_data(slot_data)

