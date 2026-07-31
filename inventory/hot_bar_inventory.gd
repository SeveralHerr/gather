extends PanelContainer

signal hot_bar_use(index: int)
signal hot_bar_stop(index: int)
signal hot_bar_selected(index: int)

const INVENTORY_SLOT = preload("res://inventory/inventory_slot.tscn")

var selected_index: int = 0
var inv: InventoryData
var style: StyleBoxFlat

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
	input_manager.gather_input_release.connect(_on_gather_stop)
	
func _process(_delta):
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
		#populate_hot_bar(inv)
		update_placed_slot()
		hot_bar_selected.emit(selected_index)
		
func _on_gather():
	hot_bar_use.emit(selected_index)
	
func _on_gather_stop():
	hot_bar_stop.emit(selected_index)
		
func set_inventory_data(inventory_data: InventoryData) -> void:
	inv = inventory_data

	inventory_data.inventory_updated.connect(populate_hot_bar)
	populate_hot_bar(inventory_data)
	hot_bar_use.connect(inventory_data.use_slot_data)
	hot_bar_stop.connect(inventory_data.stop_slot_data)
	hot_bar_selected.connect(inventory_data.show_slot_data)
	hot_bar_selected.connect(_on_select)

	style.draw_center = false
	(h_box_container.get_children()[0] as PanelContainer).add_theme_stylebox_override("panel", style)

func _on_select(_i):
	update_placed_slot()
	pass	

func populate_hot_bar(inventory_data: InventoryData) -> void:
	var selected := selected_slot_data
	if not selected or selected.count <= 0:
		held_item_texture.texture = null

	for child in h_box_container.get_children():
		child.queue_free()
		
	var hot_bar_slots = inventory_data.inventory_slot_datas.slice(0, 6)
	for index in hot_bar_slots.size():
		var slot_data = hot_bar_slots[index]
		var slot = INVENTORY_SLOT.instantiate()
		h_box_container.add_child(slot)

		slot.slot_clicked.connect(inventory_data.on_slot_clicked)

		if slot_data:
			slot.set_slot_data(slot_data)

		# Highlight by index so the selection stays put when the slot is emptied.
		if index == selected_index:
			slot.add_theme_stylebox_override("panel", style)

func update_placed_slot() -> void:
	if held_item_texture and  selected_slot_data and selected_slot_data.item and selected_slot_data.item.is_placeable:
		held_item_texture.show()
		held_item_texture.texture = selected_slot_data.item.get_atlas()
	else: 
		held_item_texture.hide()
