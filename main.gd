extends Node
class_name TileMapHandler
var resources = {}
@export var player: Player
@export var itemManager: ItemManager
@export var tileMap: TileMap
@export var items: Items
var specialTiles = []

# Called every frame. 'delta' is the elapsed time since the previous frame.
func _process(delta):
	GetPlayerPosition()

func SetResource(location, resource):
	tileMap.set_cell(1, location, 0, resource)
	
func SetGameItem(location: Vector2i, tile_source_id: int, atlas_location: Vector2i):
	tileMap.set_cell(1,location, tile_source_id, atlas_location)
	
func SetGameItemScene(location: Vector2i, tile_source_id: int, atlas_location: Vector2i):

	var found = false
	for i in range(specialTiles.size()):
		if specialTiles[i] == location:
			found = true
			
	if found == false:
		specialTiles.append(location)
		tileMap.set_cell(1,location, tile_source_id, atlas_location, 1) 
		
func SetGameResource(location: Vector2i, tile_source_id: int, atlas_location: Vector2i):
	tileMap.set_cell(1,location, tile_source_id, atlas_location)
	
func RemoveResource(location):
	tileMap.set_cell(1, location, -1)

func get_random_tile():
	# Get the used rectangle, which includes the area where tiles are placed
	var used_rect = tileMap.get_used_rect()
	
	# Generate a random position within the used rectangle
	var random_x = randi() % used_rect.size.x + used_rect.position.x
	var random_y = randi() % used_rect.size.y + used_rect.position.y

	# Get the tile index at the random position
	var tile_index = tileMap.get_cell_tile_data(1, Vector2(random_x, random_y))
	
	for i in range(specialTiles.size()):
		if specialTiles[i] == Vector2i(random_x, random_y):
			print("Special tile")
			tile_index == null

	# Optionally, if you want to keep trying random positions until you find a non-empty tile
	while tile_index:
		random_x = randi() % used_rect.size.x + used_rect.position.x
		random_y = randi() % used_rect.size.y + used_rect.position.y
		
		tile_index = tileMap.get_cell_tile_data(1, Vector2(random_x, random_y))

		for i in range(specialTiles.size()):
			if specialTiles[i] == Vector2i(random_x, random_y):
				print("Special tile")
				tile_index == null
				
	return Vector2(random_x, random_y)

func GetPlayerPosition():
	return tileMap.local_to_map(player.global_position)

