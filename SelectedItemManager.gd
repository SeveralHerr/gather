extends Control
class_name SelectedItemManager

@export var tileMapHandler: TileMapHandler
@onready var input_manager = $"../../InputManager"


var selected_inventory_slot_item: InventorySlot
var selectedTexture = TextureRect.new()

# Called when the node enters the scene tree for the first time.
func _ready():
	selectedTexture.mouse_filter = Control.MOUSE_FILTER_IGNORE
	input_manager.connect("mouse_button_left", Callable(self, "_on_click"))

func _on_click(isUiOpen: bool):
	if selectedTexture.texture != null:
		if not isUiOpen:	
			var mouse_pos = get_global_mouse_position()
			var tile_pos = tileMapHandler.tileMap.local_to_map(mouse_pos)
			if not tileMapHandler.is_occupied(tile_pos):
				tileMapHandler.set_tile(tile_pos, selected_inventory_slot_item.tile_source_id, selected_inventory_slot_item.atlas_location, selected_inventory_slot_item.layer, selected_inventory_slot_item.is_scene_tile)
			
	
func SetSelectedItem(inventory_slot_item: InventorySlot):
	selected_inventory_slot_item = inventory_slot_item
	selectedTexture.texture = inventory_slot_item.item.get_atlas()
	add_child(selectedTexture)
	
func ClearSelection():
	if selected_inventory_slot_item == null:
		return
	#selectedTexture.queue_free()
	selectedTexture.texture = null
	selected_inventory_slot_item = null



func _physics_process(delta):
	if selectedTexture.texture != null:
		var mouse_pos = get_global_mouse_position()
		var tile_pos = tileMapHandler.tileMap.local_to_map(mouse_pos)
		var clamped_world_pos = tileMapHandler.tileMap.map_to_local(tile_pos)
		clamped_world_pos -= Vector2(16, 16) / 2

		# Set the object's position to the clamped position
		selectedTexture.position = clamped_world_pos

		if tileMapHandler.is_occupied(tile_pos):
			selectedTexture.modulate = Color(1, 0, 0, 140)
		else:
			selectedTexture.modulate = Color(1, 1, 1, 1)
				
		
		
