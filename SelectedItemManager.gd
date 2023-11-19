extends Control
class_name SelectedItemManager

@export var tileMapHandler: TileMapHandler
@onready var input_manager: InputManager= $"../../../../../InputManager"



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
	add_child(selectedTexture)
	selectedTexture.z_index = 5
	selectedTexture.mouse_filter = Control.MOUSE_FILTER_IGNORE
	input_manager.connect("mouse_button_left", Callable(self, "_on_click"))

func _on_click(isUiOpen: bool):
	if selectedTexture.texture != null:
		if not input_manager.isUiOpen:	
			var mouse_pos = get_global_mouse_position()
			var tile_pos = tileMapHandler.tileMap.local_to_map(mouse_pos)
			if not tileMapHandler.is_occupied(tile_pos) and selected_inventory_slot_item.item.is_placeable:

				tileMapHandler.set_tile(tile_pos, selected_inventory_slot_item.item.tile_source_id, selected_inventory_slot_item.item.atlas_location, selected_inventory_slot_item.item.layer, selected_inventory_slot_item.item.is_scene_tile)
			
	
func SetSelectedItem(inventory_slot_item: InventorySlot, incoming_type: Type):
	if inventory_slot_item == null:
		return 
	
	selected_inventory_slot_item = inventory_slot_item
	type = incoming_type
	selectedTexture.texture = inventory_slot_item.item.get_atlas()
	
func ClearSelection():
	if selected_inventory_slot_item == null:
		return
	#selectedTexture.queue_free() 
	selectedTexture.texture = null
	selected_inventory_slot_item = null
	type = Type.None
	



func _process(delta):
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

		if tileMapHandler.is_occupied(tile_pos):
			selectedTexture.modulate = Color(1, 0, 0, 140)
		else:
			selectedTexture.modulate = Color(1, 1, 1, 1)
				
		
		
