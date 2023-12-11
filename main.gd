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
@onready var save_load: SaveLoad = $Node2D/Player/Camera2D/UI/SaveLoad
@onready var destroy_manager = $DestroyManager
var chest = preload("res://TileScenes/chest.tscn")

var wall_tiles_min = Vector2(0,7)
var wall_tiles_max = Vector2(11,11)

var ground_tiles_min = Vector2(0,15)
var ground_tiles_max = Vector2(11,18)

var radius = 6
var noise_scale = 1
var noise_threshold = 0.0
var noise = FastNoiseLite.new() # Instance of OpenSimplexNoise
var tile_index = 0 # You should set this to the appropriate tile index

var late_load = false

var disableSetTile = false
@export var save_data2 = {}

var crack = preload("res://Crack.tres")
func _ready():
	randomize()
	add_to_group("SaveLoad")
	add_to_group("TileMapHandler")
	#rain() 
	resource_manager.connect("resource_added", Callable(self, "_on_resource_added"))
	resource_manager.connect("resource_removed", Callable(self, "_on_resource_removed"))
	resource_manager.connect("resource_removing", Callable(self, "_on_resource_removing"))
	resource_manager.connect("resource_removing_stop", Callable(self, "_on_resource_removing_stop"))
	destroy_manager.connect("destroy_added", Callable(self, "_on_destroy_added"))
	destroy_manager.connect("destroy_removed", Callable(self, "_on_destroy_removed"))
	destroy_manager.connect("destroy_removing", Callable(self, "_on_destroy_removing"))
	destroy_manager.connect("destroy_removing_stop", Callable(self, "_on_destroy_removing_stop"))
	input_manager.connect("mouse_button_left", Callable(self, "_on_mouse_left"))
	noise.set_noise_type(FastNoiseLite.TYPE_PERLIN)
	
	var layers = tileMap.get_layers_count()
	var tile_grid = tileMap.get_used_cells(0)
	
	for cell in tile_grid:
		tileMap.set_cell(0, cell, -1)
	#noise.set_frequency(0.5)	
	noise.set_seed(randi())
	var lands = []
	for x in range(-radius, radius + 1):
		for y in range(-radius, radius + 1):
			var tile_position = Vector2(x, y)
			var distance = tile_position.length()

			if distance <= radius:
				var noise_value = noise.get_noise_2d(x * noise_scale, y * noise_scale)

				if noise_value < noise_threshold:
					# Place a tile at this position
					#tileMap.set_cell(1, tile_position, 4, Vector2i(0, 15),1 )
					lands.append(tile_position)
	tileMap.set_cells_terrain_connect(0, lands, 0, 1)
	
	PlayerManager.player.position = tileMap.map_to_local(lands[0])


func generate_island():
	var layers = tileMap.get_layers_count()
	var tile_grid = tileMap.get_used_cells(0)
	
	for cell in tile_grid:
		tileMap.set_cell(0, cell, -1)
	#noise.set_frequency(0.5)	
	noise.set_seed(randi())
	var lands = []
	for x in range(-radius, radius + 1):
		for y in range(-radius, radius + 1):
			var tile_position = Vector2(x, y)
			var distance = tile_position.length()

			if distance <= radius:
				var noise_value = noise.get_noise_2d(x * noise_scale, y * noise_scale)

				if noise_value < noise_threshold:
					# Place a tile at this position
					#tileMap.set_cell(1, tile_position, 4, Vector2i(0, 15),1 )
					lands.append(tile_position)
	tileMap.set_cells_terrain_connect(0, lands, 0, 1)
# Called every frame. 'delta' is the elapsed time since the previous frame.
func _process(delta):
	if late_load == true:
		save_load.late_load()
		late_load = false

	GetPlayerPosition()
	
func add_highlight(location):
	tileMap.set_cell(3, tileMap.local_to_map(location), 4, Vector2i(7, 1))

	
func remove_highlight():
	var tiles = tileMap.get_used_cells(3)
	for tile in tiles: 
		tileMap.set_cell(3, tile, -1)

	
func _on_destroy_removing(location: Vector2i, item: GameItem):
	# Add highlight
	tileMap.set_cell(3, tileMap.local_to_map(location), 4, Vector2i(7, 1))
	
	#tileMap.set_tile(tileMap.local_to_map(location),item.tile_source_id, item.atlas_location, item.layer, item.is_scene_tile)
	
func _on_destroy_added(location: Vector2i, item: GameItem):
	set_tile(location,item.tile_source_id, item.atlas_location, item.layer, item.is_scene_tile)

func _on_destroy_removed(location: Vector2i, item: GameItem):
	tileMap.set_cell(item.layer,tileMap.local_to_map(location), -1)
	tileMap.set_cell(3, tileMap.local_to_map(location), -1)
	print(tileMap.local_to_map(location))
	
	if is_wall_tile(item.atlas_location):

		var index = wallTiles.find(tileMap.local_to_map(location))
		if index != -1:
			wallTiles.remove_at(index)
			print(wallTiles)
			print(tileMap.local_to_map(player.global_position))
	replace_tiles()
	tileMap.set_cells_terrain_connect(1, wallTiles, 0, 0 , false)
	#tileMap.set_cells_terrain_path(1, [Vector2i(-3,-3), Vector2i(-3, -2)], 0, 0 , false)


func replace_tiles():
	for tile in wallTiles:
		tileMap.set_cell(1, tile, 4, Vector2i(0, 11) )
	
func _on_destroy_removing_stop(location: Vector2i, item: GameItem):
	# Remove highlight
	tileMap.set_cell(3, tileMap.local_to_map(location), -1)
	#set_tile(location,item.tile_source_id, item.atlas_location, item.layer, item.is_scene_tile)
	
	
func _on_mouse_left(isUiOpen: bool):
	disableSetTile = isUiOpen

func _on_resource_added(location: Vector2i, resource: GameResource):
	set_tile(location,resource.tile_source_id, resource.atlas_location, resource.layer)

func _on_resource_removed(location: Vector2i, resource: GameResource):
	if resource.type == Types.Item.StoneResource or resource.type == Types.Item.CoalResource or resource.type == Types.Item.IronResource:
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
	
func set_tile_item(location: Vector2i, item: GameItem):
	set_tile(location,item.tile_source_id, item.tile_atlas_location, item.layer, item.is_scene_tile)
	
func set_tile(location: Vector2i, tile_source_id: int, atlas_location: Vector2i, layer: int, is_scene: bool = false):
	if disableSetTile == true:
		return
	
	play_audio(location, tile_source_id, atlas_location, layer, is_scene)
	tileMap.set_cell(layer, location, tile_source_id, atlas_location, is_scene)

	if atlas_location.x >= wall_tiles_min.x and atlas_location.y >= wall_tiles_min.y and atlas_location.x <= wall_tiles_max.x and atlas_location.y <= wall_tiles_max.y:
		atlas_location = Vector2(0, 11)
		wallTiles.append(location)
		tileMap.set_cells_terrain_connect(1, wallTiles, 0, 0 )
		
func is_wall_tile(atlas_location):
	if atlas_location.x >= wall_tiles_min.x and atlas_location.y >= wall_tiles_min.y and atlas_location.x <= wall_tiles_max.x and atlas_location.y <= wall_tiles_max.y:
		return true
	return false
		
func play_audio(location: Vector2i, tile_source_id: int, atlas_location: Vector2i, layer: int, is_scene: bool = false):
	var item = items.get_item_by_data(atlas_location, tile_source_id)
	if atlas_location.x >= wall_tiles_min.x and atlas_location.y >= wall_tiles_min.y and atlas_location.x <= wall_tiles_max.x and atlas_location.y <= wall_tiles_max.y:
		sound_manager.play_sound(sound_manager.SoundType.WOOD_PLACE)
	elif item and ( item.type == Types.Item.Chest or item.type == Types.Item.WoodDoor or item.type == Types.Item.Sawmill or item.type == Types.Item.WoodFloor):
			sound_manager.play_sound(sound_manager.SoundType.WOOD_PLACE)
	
func is_occupied(tilePos: Vector2i, include_resources = false, is_wall: bool = false)-> bool:
	var is_occupied = false
	
	if is_wall == true:
		return false
	
	var tile = tileMap.get_cell_tile_data(1, tilePos)
	if tile != null:
		is_occupied = true
		
	tile = tileMap.get_cell_tile_data(2, tilePos)
	if tile != null and include_resources == true:
		is_occupied = true
		
	# Check if trying to spawn on anything that is not grass
	if tileMap.get_cell_atlas_coords(0, tilePos) != Vector2i(9, 17):
		is_occupied = true
	
	
	var atlas_location = tileMap.get_cell_atlas_coords(1, tilePos)
	var source_id = tileMap.get_cell_source_id (1, tilePos)
	var item = resources.get_item_or_resource(atlas_location, source_id)
	
	if item != null and item.is_scene_tile:
		is_occupied = true
			

	return is_occupied
		
func RemoveResource(location):
	tileMap.set_cell(1, location, -1)

func get_random_position_within_rect(rect):
	var random_x = randi() % rect.size.x + rect.position.x
	var random_y = randi() % rect.size.y + rect.position.y
	return Vector2(random_x, random_y)
	
func get_mouse_tile_position():
	var mouse_pos = get_viewport().get_mouse_position()
	var tile_pos = tileMap.local_to_map(mouse_pos)
	var tile_center_global = tileMap.map_to_local(tile_pos) - Vector2(8, 8)

	tile_center_global = tileMap.map_to_local(tile_pos)
	tile_center_global -= Vector2(16, 16) / 2
	tile_center_global = mouse_pos
	
	return tile_center_global
	
func get_tile_in_front_of_player():
		var tile_pos = tileMap.local_to_map(PlayerManager.player.get_global_position())
		if PlayerManager.player.is_facing_left():
			tile_pos += Vector2i(-1, 0)
			pass
		else:
			tile_pos += Vector2i(1, 0)
			pass
			
		#var tile_center_global = tileMap.map_to_local(tile_pos) - Vector2(8, 8)

		return tileMap.map_to_local(tile_pos) - Vector2(8, 8)
	
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

func get_location_of_nearby_item_to_destroy(location):
	var neighbors = [Vector2i.UP, Vector2i.DOWN, Vector2i.LEFT, Vector2i.RIGHT, Vector2i.UP + Vector2i.LEFT, Vector2i.UP + Vector2i.RIGHT, Vector2i.DOWN + Vector2i.LEFT, Vector2i.DOWN + Vector2i.RIGHT, Vector2i.ZERO]
	var nearestDistance = 1000000
	var nearestPos = null
	
	for neighbor in neighbors:
		var tilePos = tileMap.local_to_map(location) + neighbor
		var tile_atlas = tileMap.get_cell_atlas_coords(1, tilePos)
		var tile_source_id = tileMap.get_cell_source_id(1, tilePos)
		var item = null
		
		if tile_atlas == Vector2i(-1,-1):
			continue

		if tile_atlas.x >= wall_tiles_min.x and tile_atlas.y >= wall_tiles_min.y and tile_atlas.x <= wall_tiles_max.x and tile_atlas.y <= wall_tiles_max.y:
			tile_atlas = Vector2i(0, 11)


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
		var tile_atlas = tileMap.get_cell_atlas_coords(1, nearestPos)
		var tile_source_id = tileMap.get_cell_source_id(1, nearestPos)
		for key in items.get_all_types():
			if tile_atlas.x >= wall_tiles_min.x and tile_atlas.y >= wall_tiles_min.y and tile_atlas.x <= wall_tiles_max.x and tile_atlas.y <= wall_tiles_max.y:
				tile_atlas = Vector2i(0, 11)
			if items.get_item(key).atlas_location == tile_atlas and items.get_item(key).tile_source_id == tile_source_id:
				return { "item": items.get_item(key),  "location": tileMap.map_to_local(nearestPos) }

			
func get_location_of_nearby_resource(location):
	var neighbors = [Vector2i.UP, Vector2i.DOWN, Vector2i.LEFT, Vector2i.RIGHT, Vector2i.UP + Vector2i.LEFT, Vector2i.UP + Vector2i.RIGHT, Vector2i.DOWN + Vector2i.LEFT, Vector2i.DOWN + Vector2i.RIGHT, Vector2i.ZERO]
	var nearestDistance = 1000000
	var nearestPos = null
	
	for neighbor in neighbors:
		var tilePos = tileMap.local_to_map(location) + neighbor
		var tile = tileMap.get_cell_atlas_coords(1, tilePos)
		
		if tile == Vector2i(-1,-1):
			continue
			
		var found = false
		for key in resources.GetAllTypes():
			if resources.Get(key).atlas_location == tile:
				found = true
		
		if found == false:
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


func rain():
	var amt = 19
	for i in amt:
		var tile = get_random_tile()
		tileMap.set_cell(1, tile, 7, Vector2(0,0))
		get_tree().create_timer(0.1).timeout

func get_random_tile():
	# Get the used rectangle, which includes the area where tiles are placed
	var used_tiles = []
	var ground = tileMap.get_used_cells(0)
	for i in ground.size():
		var atlas = tileMap.get_cell_atlas_coords(0, ground[i])
		if atlas == Vector2i(9, 17):
			used_tiles.append(ground[i])
		
	if not used_tiles:
		return
	
	var max_retries = 100
	var try = 1
	var random_x
	var random_y


	# Optionally, if you want to keep trying random positions until you find a non-empty tile
	while try < max_retries:
		var random_index = randi() % used_tiles.size()
		var random_tile = used_tiles[random_index]
		
		if is_occupied(Vector2i(random_tile.x, random_tile.y), true):
			try += 1
			continue
		
			
		try += 1
		return Vector2i(random_tile.x, random_tile.y)
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
			if atlas_location.x >= wall_tiles_min.x and atlas_location.y >= wall_tiles_min.y and atlas_location.x <= wall_tiles_max.x and atlas_location.y <= wall_tiles_max.y:
				item = items.get_item(Types.Item.WoodWall)
			elif  atlas_location.x >= ground_tiles_min.x and atlas_location.y >= ground_tiles_min.y and atlas_location.x <= ground_tiles_max.x and atlas_location.y <= ground_tiles_max.y:
				item = items.get_item(Types.Item.Ground)
			
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
	var ground_tiles = []
	
	for layer in layers:
		if layer == 0:
			continue
		
		for cell in tile_grid:
			tileMap.set_cell(layer, cell, -1)
			
	var used_rect = tileMap.get_used_rect()
	for x in range(used_rect.position.x, used_rect.position.x + used_rect.size.x):
		for y in range(used_rect.position.y, used_rect.position.y + used_rect.size.y):
			var cell = Vector2(x, y)
			var water = GameItems.get_item(Types.Item.Water)
			tileMap.set_cell(water.layer, cell, water.tile_source_id, water.atlas_location)
		
	for i in loadedDict.tiles.size():
		var saved_info = loadedDict.tiles[i]
		var json = JSON.new()
		json.parse(saved_info)
		var node = json.get_data()

		var item = resources.get_item_or_resource_by_type(node["type"])
		
		var location = Vector2i(node["x"], node["y"])
		if item.type == Types.Item.Ground:
			ground_tiles.append(location)

	
		set_tile(location, item.tile_source_id, item.atlas_location, item.layer,item.is_scene_tile)
		tileMap.set_cells_terrain_connect(0, ground_tiles, 0, 1)
	late_load = true

