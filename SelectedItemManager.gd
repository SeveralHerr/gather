extends Control
class_name SelectedItemManager

@export var tileMapHandler: TileMapHandler

var selectedItem
var selectedTexture = TextureRect.new()

# Called when the node enters the scene tree for the first time.
func _ready():
	selectedTexture.mouse_filter = Control.MOUSE_FILTER_IGNORE

#func _process(delta):
	
	
func SetSelectedItem(item: GameItem):
	selectedItem = item
	
	var location = Rect2(item.atlas_location.x*16, item.atlas_location.y*16, 16, 16)
	
	var atlas_texture = AtlasTexture.new()
	atlas_texture.atlas = load("res://Resources/game_items_atlas.tres")
	atlas_texture.region = location
	
	selectedTexture.texture = atlas_texture
	add_child(selectedTexture)
	
func ClearSelection():
	if selectedItem == null:
		return
	selectedTexture.queue_free()
	selectedTexture = TextureRect.new()
	selectedItem = null

func Place():
	var mouse_pos = get_global_mouse_position()
	var tile_pos = tileMapHandler.tileMap.local_to_map(mouse_pos)
	tileMapHandler.SetResource(tile_pos, selectedItem.atlas_location)

func _physics_process(delta):
	if selectedTexture.texture != null:
		var mouse_pos = get_global_mouse_position()
		var tile_pos = tileMapHandler.tileMap.local_to_map(mouse_pos)
		var clamped_world_pos = tileMapHandler.tileMap.map_to_local(tile_pos)
		clamped_world_pos -= Vector2(16, 16) / 2

		# Set the object's position to the clamped position
		selectedTexture.position = clamped_world_pos
		
		
