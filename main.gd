extends Node
class_name TileMapHandler
var resources = {}
@export var player: Player
@export var itemManager: ItemManager
@export var tileMap: TileMap
@export var items: Items
@export var specialTiles = []

# Called every frame. 'delta' is the elapsed time since the previous frame.
func _process(delta):
	GetPlayerPosition()

func SetResource(location, resource):
	tileMap.set_cell(1, location, 4, resource)
	
func SetGameItem(location: Vector2i, tile_source_id: int, atlas_location: Vector2i, layer: int):
	tileMap.set_cell(layer,location, tile_source_id, atlas_location)
	
	if layer == 2:
		specialTiles.append(location)
		
func AddSpecialTile(location):
	for tile in specialTiles:
		if tile == location:
			return
	
	specialTiles.append(location)

	
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

func get_random_position_within_rect(rect):
	var random_x = randi() % rect.size.x + rect.position.x
	var random_y = randi() % rect.size.y + rect.position.y
	return Vector2(random_x, random_y)

func is_special_tile(pos, special_tiles):
	for special_tile in special_tiles:
		if pos == special_tile:
			print("found special")
			return true
	return false

func get_random_tile():
	# Get the used rectangle, which includes the area where tiles are placed
	var used_rect = tileMap.get_used_rect()
	var max_retries = 100
	var try = 1
	var random_x
	var random_y


	# Optionally, if you want to keep trying random positions until you find a non-empty tile
	while try < max_retries:
		random_x = randi() % used_rect.size.x + used_rect.position.x
		random_y = randi() % used_rect.size.y + used_rect.position.y
		
		if is_special_tile(Vector2i(random_x, random_y), specialTiles):
			continue
			
		var tile = tileMap.get_cell_tile_data(1, Vector2(random_x, random_y))
		if tile != null:
			continue
			
		try += 1
		return Vector2i(random_x, random_y)
	return null
	
func gfet_random_tile():
	var used_rect = tileMap.get_used_rect()
	var tile_index
	var random_x
	var random_y

	while true:
		random_x = randi() % used_rect.size.x + used_rect.position.x
		random_y = randi() % used_rect.size.y + used_rect.position.y
		tile_index = tileMap.get_cell_tile_data(1, Vector2(random_x, random_y))

		if tile_index != null and not is_special_tile(Vector2i(random_x, random_y), specialTiles):
			# If it's a valid tile and not a special tile, break the loop
			break

	# At this point, random_pos is a valid position, so we return it
	return Vector2(random_x, random_y)

func GetPlayerPosition():
	return tileMap.local_to_map(player.global_position)

