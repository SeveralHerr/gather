extends Control
class_name SelectedItemManager

@export var tileMapHandler: TileMapHandler

var selectedItem: GameItem
var selectedTexture = TextureRect.new()

# Called when the node enters the scene tree for the first time.
func _ready():
	selectedTexture.mouse_filter = Control.MOUSE_FILTER_IGNORE

#func _process(delta):
	
	
func SetSelectedItem(item: GameItem):
	selectedItem = item
	selectedTexture.texture = item.get_atlas()
	add_child(selectedTexture)
	
func ClearSelection():
	if selectedItem == null:
		return
	selectedTexture.queue_free()
	selectedTexture = TextureRect.new()
	selectedItem = null



func _physics_process(delta):
	if selectedTexture.texture != null:
		var mouse_pos = get_global_mouse_position()
		var tile_pos = tileMapHandler.tileMap.local_to_map(mouse_pos)
		var clamped_world_pos = tileMapHandler.tileMap.map_to_local(tile_pos)
		clamped_world_pos -= Vector2(16, 16) / 2

		# Set the object's position to the clamped position
		selectedTexture.position = clamped_world_pos

		if tileMapHandler.IsTileOccupied(tile_pos):
			selectedTexture.modulate = Color(1, 0, 0, 140)
		else:
			selectedTexture.modulate = Color(1, 1, 1, 1)
			if Input.is_mouse_button_pressed(MOUSE_BUTTON_LEFT):
				tileMapHandler.SetGameItem(tile_pos, selectedItem.tile_source_id, selectedItem.atlas_location, selectedItem.layer)
		
		
