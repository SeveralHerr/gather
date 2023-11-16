extends Node
class_name TileMapHandler

signal resource_found(resource, location)  

@export var player: Player
@export var itemManager: ItemManager
@export var tileMap: TileMap
@export var items: Items
@export var specialTiles = []
var wallTiles = []
@export var resource_manager: ResourceManager2
@export var resources: Resources
@export var sound_manager: SoundManager
@onready var input_manager = $InputManager

var disableSetTile = false
@export var save_data2 = {}

var crack = preload("res://Crack.tres")
func _ready():
	add_to_group("SaveLoad")
	resource_manager.connect("resource_added", Callable(self, "_on_resource_added"))
	resource_manager.connect("resource_removed", Callable(self, "_on_resource_removed"))
	resource_manager.connect("resource_removing", Callable(self, "_on_resource_removing"))
	resource_manager.connect("resource_removing_stop", Callable(self, "_on_resource_removing_stop"))
	input_manager.connect("mouse_button_left", Callable(self, "_on_mouse_left"))

# Called every frame. 'delta' is the elapsed time since the previous frame.
func _process(delta):
	GetPlayerPosition()
	
func _on_mouse_left(isUiOpen: bool):
	disableSetTile = true

	
func _on_resource_added(location: Vector2i, resource: GameResource):
	set_tile(location,resource.tile_source_id, resource.atlas_location, resource.layer)

func _on_resource_removed(location: Vector2i, resource: GameResource):
	if resource.type == Types.Item.Stone:
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
	
func set_tile(location: Vector2i, tile_source_id: int, atlas_location: Vector2i, layer: int, is_scene: bool = false):
	if disableSetTile == true:
		return
	
	tileMap.set_cell(layer, location, tile_source_id, atlas_location, is_scene)
	
	if atlas_location == Vector2i(0, 11):
		wallTiles.append(location)
		tileMap.set_cells_terrain_connect(1, wallTiles, 0, 0 )
	
func is_occupied(tilePos: Vector2i)-> bool:
	var is_occupied = false
	
	var tile = tileMap.get_cell_tile_data(1, tilePos)
	if tile != null:
		is_occupied = true
		
	tile = tileMap.get_cell_tile_data(2, tilePos)
	if tile != null:
		is_occupied = true

	return is_occupied
		
func RemoveResource(location):
	tileMap.set_cell(1, location, -1)

func get_random_position_within_rect(rect):
	var random_x = randi() % rect.size.x + rect.position.x
	var random_y = randi() % rect.size.y + rect.position.y
	return Vector2(random_x, random_y)
	
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

func place_auto_tile( atlas_location):
	# Set the tile at the specified cell position.
	tileMap.set_cell(3, Vector2i(1, 1), 4, atlas_location) 
	tileMap.set_cell(3, Vector2i(1, 2), 4, atlas_location ) 
	tileMap.set_cell(3, Vector2i(0, 2), 4, atlas_location) 
	# Update the bitmasks to apply auto-tiling rules.
	#tileMap.bitma(cell_position - Vector2(1, 1), cell_position + Vector2(1, 1))
	tileMap.set_cells_terrain_connect(3, wallTiles, 0, 0 )


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
		
		if is_occupied(Vector2i(random_x, random_y)):
			continue
			
		try += 1
		return Vector2i(random_x, random_y)
	return null

func GetPlayerPosition():
	return tileMap.local_to_map(player.global_position)
	
func saveObject() -> Dictionary:
	var tile_layers = []
	var layers = tileMap.get_layers_count()
	var tile_grid = tileMap.get_used_cells(0)
	
	for layer in layers:
		for cell in tile_grid:
			var atlas_location = tileMap.get_cell_atlas_coords(layer, cell)
			var source_id = tileMap.get_cell_source_id (layer, cell)
			var item = resources.get_item_or_resource(atlas_location, source_id)
			
			if item == null:
				continue

			var json = {
				"type": item.type,
				"x": cell.x,
				"y": cell.y
			}

			tile_layers.append(JSON.stringify(json))
			
	var dict := {
		"filepath": get_path(),
		"tiles": tile_layers
	}
	
	return dict
			
func loadObject(loadedDict: Dictionary) -> void:	
	var layers = tileMap.get_layers_count()
	var tile_grid = tileMap.get_used_cells(0)
	wallTiles = []
	
	for layer in layers:
		for cell in tile_grid:
			tileMap.set_cell(layer, cell, -1)
	
	for i in loadedDict.tiles.size():
		var saved_info = loadedDict.tiles[i]
		var json = JSON.new()
		json.parse(saved_info)
		var node = json.get_data()

		var item = resources.get_item_or_resource_by_type(node["type"])
		var location = Vector2i(node["x"], node["y"])
		
		tileMap.set_cell(item.layer, location, item.tile_source_id, item.atlas_location, item.is_scene_tile)

