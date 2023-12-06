extends PanelContainer

signal hot_bar_use(index: int)
signal hot_bar_selected(index: int)

const INVENTORY_SLOT = preload("res://Inventory/InventorySlot.tscn")

var selected_slot_data: SlotData
var selected_index: int
var inv: InventoryData
var style: StyleBoxFlat

@onready var h_box_container: HBoxContainer = $MarginContainer/HBoxContainer

func _ready():
	style = StyleBoxFlat.new()
	style.border_width_bottom = 2
	style.border_width_left = 2
	style.border_width_right = 2
	style.border_width_top = 2

func _unhandled_key_input(event):
	if not visible or not event.is_pressed():
		return
	
	if range(KEY_1, KEY_7).has(event.keycode):
		for child in h_box_container.get_children():
			var panel = child as PanelContainer
			panel.remove_theme_stylebox_override("panel")
		
		var slot = h_box_container.get_child(event.keycode - KEY_1) as PanelContainer
		slot.add_theme_stylebox_override("panel", style)
		selected_index = event.keycode - KEY_1
		selected_slot_data = inv.inventory_slot_datas[selected_index]
		hot_bar_selected.emit(selected_index)
		
func _process(delta):
	if Input.is_action_just_pressed("gather"):
		hot_bar_use.emit(selected_index)

func set_inventory_data(inventory_data: InventoryData) -> void:
	if not selected_slot_data:
		selected_slot_data = inventory_data.inventory_slot_datas[0]
		
		
	inventory_data.inventory_updated.connect(populate_hot_bar)
	populate_hot_bar(inventory_data)
	hot_bar_use.connect(inventory_data.use_slot_data)
	hot_bar_selected.connect(inventory_data.show_slot_data)
	inv = inventory_data

	style.draw_center = false
	(h_box_container.get_children()[0] as PanelContainer).add_theme_stylebox_override("panel", style)

func populate_hot_bar(inventory_data: InventoryData) -> void:
	for child in h_box_container.get_children():
		child.queue_free()
		
	for slot_data in inventory_data.inventory_slot_datas.slice(0, 6):
		var slot = INVENTORY_SLOT.instantiate()
		h_box_container.add_child(slot)
		
		slot.slot_clicked.connect(inventory_data.on_slot_clicked)
		
		if slot_data:
			slot.set_slot_data(slot_data)
			if slot_data == selected_slot_data:
				slot.add_theme_stylebox_override("panel", style)

