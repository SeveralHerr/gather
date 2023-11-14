extends Node
class_name TileMapHandler

signal resource_found(resource, location)  

@export var player: Player
@export var itemManager: ItemManager
@export var tileMap: TileMap
@export var items: Items
@export var specialTiles = []
@export var resource_manager: ResourceManager2
@export var resources: Resources
@export var sound_manager: SoundManager

var crack = preload("res://Crack.tres")
func _ready():
	resource_manager.connect("resource_added", Callable(self, "_on_resource_added"))
	resource_manager.connect("resource_removed", Callable(self, "_on_resource_removed"))
	resource_manager.connect("resource_removing", Callable(self, "_on_resource_removing"))
	resource_manager.connect("resource_removing_stop", Callable(self, "_on_resource_removing_stop"))

# Called every frame. 'delta' is the elapsed time since the previous frame.
func _process(delta):
	GetPlayerPosition()
	
func _on_resource_added(location: Vector2i, resource: GameResource):
	SetResource(location, resource.atlas_location)

func _on_resource_removed(location: Vector2i, resource: GameResource):
	if resource.type == GameResource.Type.Stone:
		sound_manager.play_sound(SoundManager.SoundType.STONE)
	
	clear_tile(tileMap.local_to_map(location))

func _on_resource_removing(location: Vector2i, resource: GameResource):
	# Add highlight
	tileMap.set_cell(3, tileMap.local_to_map(location), 4, Vector2i(7, 1))
	
	if resource.gathering_atlas_location != Vector2i.ZERO:
		tileMap.set_cell(1, tileMap.local_to_map(location), 4, resource.gathering_atlas_location)
	
func _on_resource_removing_stop(location: Vector2i, resource: GameResource):
	# Remove highlight
	tileMap.set_cell(3, tileMap.local_to_map(location), -1)
	
	if resource.gathering_atlas_location != Vector2i.ZERO:
		tileMap.set_cell(1, tileMap.local_to_map(location), 4, resource.atlas_location)

func clear_tile(location: Vector2i):
	# Remove highlight
	tileMap.set_cell(3, location, -1)
	tileMap.set_cell(1, location, -1)
	

func SetResource(location, resource):
	tileMap.set_cell(1, location, 4, resource)
	
func SetGameItem(location: Vector2i, tile_source_id: int, atlas_location: Vector2i, layer: int):
	tileMap.set_cell(layer,location, tile_source_id, atlas_location)
	
	if layer == 2:
		AddSpecialTile(location)
		
func AddSpecialTile(location):
	for tile in specialTiles:
		if tile == location:
			return
	
	specialTiles.append(location)
	
func IsTileOccupied(tilePos: Vector2i)-> bool:
	if is_special_tile(tilePos, specialTiles):
		return true
	
	var tile = tileMap.get_cell_tile_data(1, tilePos)
	if tile != null:
		return true

	return false
	
	
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

			return true
	return false
	
func _find_nearest_tile_and_resource(location: Vector2):
	var neighbors = [Vector2i.UP, Vector2i.DOWN, Vector2i.LEFT, Vector2i.RIGHT, Vector2i.UP + Vector2i.LEFT, Vector2i.UP + Vector2i.RIGHT, Vector2i.DOWN + Vector2i.LEFT, Vector2i.DOWN + Vector2i.RIGHT, Vector2i.ZERO]
	var nearestDistance = 1000000
	var nearestPos = null

	for neighbor in neighbors:
		var tilePos = tileMap.local_to_map(location) + neighbor
		var tile = tileMap.get_cell_atlas_coords(1, tilePos)
		if tile == Vector2i(-1,-1):
			continue
		
		var direction = player.global_position - tileMap.map_to_local(tilePos)
		var distance = direction.length()
		if distance < nearestDistance:
			nearestDistance = distance
			nearestPos = tilePos
			
	if nearestPos == null:
		return
			
	var direction = location - tileMap.map_to_local(nearestPos)
	var distance = direction.length()
	var activation_distance = 20
	
	if distance < activation_distance and distance > 0:
		var tile = tileMap.get_cell_atlas_coords (1, nearestPos)
		for key in resources.GetAllTypes():
			if resources.Get(key).atlas_location == tile:
				return resources.Get(key)
				
func find_nearest_resource_to_location(location: Vector2):
	var nearest_resource_info = get_location_of_nearby_resource(location)
	if nearest_resource_info:
		emit_signal("resource_found", nearest_resource_info.resource, nearest_resource_info.location)

			
func get_location_of_nearby_resource(location):
	var neighbors = [Vector2i.UP, Vector2i.DOWN, Vector2i.LEFT, Vector2i.RIGHT, Vector2i.UP + Vector2i.LEFT, Vector2i.UP + Vector2i.RIGHT, Vector2i.DOWN + Vector2i.LEFT, Vector2i.DOWN + Vector2i.RIGHT, Vector2i.ZERO]
	var nearestDistance = 1000000
	var nearestPos = null
	
	for neighbor in neighbors:
		var tilePos = tileMap.local_to_map(location) + neighbor
		var tile = tileMap.get_cell_atlas_coords(1, tilePos)
		if tile == Vector2i(-1,-1):
			continue
		
		var direction = player.global_position - tileMap.map_to_local(tilePos)
		var distance = direction.length()
		if distance < nearestDistance:
			nearestDistance = distance
			nearestPos = tilePos
			
	if nearestPos == null:
		return
			
	var direction = location - tileMap.map_to_local(nearestPos)
	var distance = direction.length()
	var activation_distance = 20
	
	if distance < activation_distance and distance > 0:
		var tile = tileMap.get_cell_atlas_coords (1, nearestPos)
		for key in resources.GetAllTypes():
			if resources.Get(key).atlas_location == tile:

				return { "resource": resources.Get(key),  "location": tileMap.map_to_local(nearestPos) }

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

