extends PanelContainer

signal hot_bar_use(index: int)
signal hot_bar_selected(index: int)

const INVENTORY_SLOT = preload("res://Inventory/InventorySlot.tscn")

var selected_slot_data: SlotData
var selected_index: int
var inv: InventoryData
var style: StyleBoxFlat

@onready var h_box_container: HBoxContainer = $MarginContainer/HBoxContainer
@onready var input_manager: InputManager = $"../../InputManager"
@onready var held_item_texture: TextureRect = $"../../Node2D/Player/HeldItemTexture"
@onready var tile_map: TileMapHandler = $"../.."



func _ready():
	style = StyleBoxFlat.new()
	style.border_width_bottom = 2
	style.border_width_left = 2
	style.border_width_right = 2
	style.border_width_top = 2
	
	input_manager.gather_input_press.connect(_on_gather)
	
func _process(delta):
	if held_item_texture.visible:
		var tile_pos =  tile_map.get_tile_in_front_of_player()
		held_item_texture.global_position = tile_pos
		
		if tile_map.is_occupied(tile_map.tileMap.local_to_map(tile_pos), true, false):
			held_item_texture.modulate = Color(1, 0, 0, 140)
		else:
			held_item_texture.modulate = Color(1, 1, 1, 1)
		
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
		#populate_hot_bar(inv)
		update_placed_slot()
		hot_bar_selected.emit(selected_index)
		
func _on_gather():
	hot_bar_use.emit(selected_index)
		
func set_inventory_data(inventory_data: InventoryData) -> void:
	if not selected_slot_data:
		selected_slot_data = inventory_data.inventory_slot_datas[0]
		
		
	inventory_data.inventory_updated.connect(populate_hot_bar)
	populate_hot_bar(inventory_data)
	hot_bar_use.connect(inventory_data.use_slot_data)
	hot_bar_selected.connect(inventory_data.show_slot_data)
	hot_bar_selected.connect(_on_select)

	inv = inventory_data

	style.draw_center = false
	(h_box_container.get_children()[0] as PanelContainer).add_theme_stylebox_override("panel", style)

func _on_select(i):
	update_placed_slot()
	pass	

func populate_hot_bar(inventory_data: InventoryData) -> void:
	if selected_slot_data.count <= 0:
		held_item_texture.texture = null
	
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

func update_placed_slot() -> void:
	if held_item_texture and  selected_slot_data and selected_slot_data.item and selected_slot_data.item.is_placeable:
		held_item_texture.show()
		held_item_texture.texture = selected_slot_data.item.get_atlas()
	else: 
		held_item_texture.hide()
