extends Control
class_name SelectedItemManager

@export var tileMapHandler: TileMapHandler
@onready var input_manager: InputManager= $"../../../../../InputManager"
@onready var inventory_manager: InventoryManager = $"../../../../../InventoryManager"


signal placed_tile(item: GameItem)
signal selected_item(item: GameItem)



var selected_inventory_slot_item: InventorySlot
var selectedTexture = TextureRect.new()
var type: Type = Type.None

enum Type {
	None,
	Inventory,
	Chest,
	Crafting
}

# Called when the node enters the scene tree for the first time.
func _ready():
	add_to_group("SelectedItemManager")
	add_child(selectedTexture)
	selectedTexture.z_index = 5
	selectedTexture.mouse_filter = Control.MOUSE_FILTER_IGNORE
	input_manager.connect("mouse_button_left", Callable(self, "_on_click"))

func _on_click(isUiOpen: bool):
	if selectedTexture.texture == null:
		return
		
	if input_manager.isUiOpen:	
		return
		

	
	var mouse_pos = get_global_mouse_position()
	var tile_pos = tileMapHandler.tileMap.local_to_map(mouse_pos)
	var is_wall = selected_inventory_slot_item.item.type == Types.Item.WoodFloor
	if not tileMapHandler.is_occupied(tile_pos, true, is_wall) and selected_inventory_slot_item.item.is_placeable:
		tileMapHandler.set_tile(tile_pos, selected_inventory_slot_item.item.tile_source_id, selected_inventory_slot_item.item.atlas_location, selected_inventory_slot_item.item.layer, selected_inventory_slot_item.item.is_scene_tile)
		placed_tile.emit(selected_inventory_slot_item.item)

		#if selected_inventory_slot_item.item
	
func has_selected_item()-> bool: 
	return selected_inventory_slot_item != null
	
func get_selected_item_type():
	return selected_inventory_slot_item.item.type
	
func get_selected_item():
	return selected_inventory_slot_item.item
	
func get_selected_inventory_slot():
	return selected_inventory_slot_item
	
func SetSelectedItem(inventory_slot_item: InventorySlot, incoming_type: Type):
	if inventory_slot_item == null:
		return 
	
	selected_inventory_slot_item = inventory_slot_item
	selected_item.emit(inventory_slot_item.item)
	type = incoming_type
	
	if selected_inventory_slot_item.item.is_placeable:
		selectedTexture.texture = inventory_slot_item.item.get_atlas()
	
func ClearSelection():
	if selected_inventory_slot_item == null:
		return
		

	#selectedTexture.queue_free() 
	selectedTexture.texture = null
	#selected_inventory_slot_item.item = null
	selected_inventory_slot_item = null
	type = Type.None
	



func _process(_delta):
	if selectedTexture.texture != null:

		var mouse_pos = get_global_mouse_position()
		var tile_pos = tileMapHandler.tileMap.local_to_map(mouse_pos)
		var tile_center_global = tileMapHandler.tileMap.map_to_local(tile_pos) - Vector2(8, 8)

		if input_manager.isUiOpen:
			# clamp to tile
			tile_center_global = tileMapHandler.tileMap.map_to_local(tile_pos)
			tile_center_global -= Vector2(16, 16) / 2
			tile_center_global = mouse_pos
			

		# Set the object's position to the clamped position
		selectedTexture.global_position = tile_center_global

		var is_wall = selected_inventory_slot_item.item.type == Types.Item.WoodFloor
		if tileMapHandler.is_occupied(tile_pos, true, is_wall):
			selectedTexture.modulate = Color(1, 0, 0, 140)
		else:
			selectedTexture.modulate = Color(1, 1, 1, 1)
				
		
		
