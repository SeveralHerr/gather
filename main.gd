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

@export var save_data2 = {}

var crack = preload("res://Crack.tres")
func _ready():
	AddSpecialTile(Vector2i(123123,12312))
	add_to_group("SaveLoad")
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
	if atlas_location == Vector2i(0, 11):
		wallTiles.append(location)
		tileMap.set_cells_terrain_connect(1, wallTiles, 0, 0 )
	else:
		
		
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
		print(specialTiles)
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
	
func saveObject() -> Dictionary:
	var tileLayers = []
	var save_data1 = {}
	var special_tile_data = {}
	save_data2 = {}

	for cell in tileMap.get_used_cells(0):
		var tile_data = {}
		var atlas_location = tileMap.get_cell_atlas_coords(2, cell)
		var source_id = tileMap.get_cell_source_id(2, cell)
		var item = items.get_item_by_data(atlas_location, source_id)
		#var layer = tileMap.get
		#tile_data[cell] = item
		# You can also save other relevant information, such as collision data, metadata, etc.
		var json = {}
		if item == null:
			json =  {
				"x": cell.x,
				"y": cell.y,
				"layer": 2,
				}
		else:
			json = {
				"atlas_location_x": item.atlas_location.x,
				"atlas_location_y": item.atlas_location.y,
				"layer": 2,
				"source_id": item.tile_source_id, 
				"x": cell.x,
				"y": cell.y
			}
		save_data1[cell] = JSON.stringify(json)
	
	#resources
	for cell in tileMap.get_used_cells(0):
		var tile_data = {}
		var atlas_location = tileMap.get_cell_atlas_coords(1, cell)
		var source_id = tileMap.get_cell_source_id(1, cell)
		var item = resources.get_item_by_data(atlas_location, source_id)
		#var layer = tileMap.get
		#tile_data[cell] = item
		# You can also save other relevant information, such as collision data, metadata, etc.
		var json = {}
		if item == null:
			json =  {
				"x": cell.x,
				"y": cell.y,
				"layer": 1,
					}
		else:
			json = {
				"atlas_location_x": item.atlas_location.x,
				"atlas_location_y": item.atlas_location.y,
				"layer": 1,
				"source_id": item.tile_source_id, 
				"x": cell.x,
				"y": cell.y
			}
		save_data2[cell] = JSON.stringify(json)
		
	# specials
	for cell in tileMap.get_used_cells(0):
		var tile_data = {}
		var atlas_location = tileMap.get_cell_atlas_coords(1, cell)
		var source_id = tileMap.get_cell_source_id(1, cell)
		var item = items.get_item_by_data(atlas_location, source_id)
		
		if source_id ==  5 or source_id == 2:			
			var json = {}
			if item == null:
				json =  {
					"x": cell.x,
					"y": cell.y,
					"layer": 1,
						}
			else:
				json = {
					"atlas_location_x": item.atlas_location.x,
					"atlas_location_y": item.atlas_location.y,
					"layer": 1,
					"source_id": item.tile_source_id, 
					"x": cell.x,
					"y": cell.y
				}
			special_tile_data[cell] = JSON.stringify(json)

		
		tileLayers = [save_data2, save_data1, special_tile_data]
	
	var dict := {
		"filepath": get_path(),
		"save_data2": tileLayers
	}
	return dict
	
func loadObject(loadedDict: Dictionary) -> void:
	for cell in loadedDict.save_data2[0].keys():

		#var cell_vector = Vector2(int(cell.split(",")[0]), int(cell.split(",")[1]))
		var item = loadedDict.save_data2[0][cell]
		var json = JSON.new()
		json.parse(item)
		var node = json.get_data()
		if not node.has("source_id"):

			
			tileMap.set_cell(3, Vector2i(node["x"], node["y"]), -1)
			tileMap.set_cell(node["layer"], Vector2i(node["x"], node["y"]), -1)
			continue


		tileMap.set_cell(node["layer"], Vector2i(node["x"], node["y"]), node["source_id"],Vector2i( node["atlas_location_x"], node["atlas_location_y"] ))
		# Restore any other tile properties you saved previously.
		
	for cell in loadedDict.save_data2[1].keys():
		#var cell_vector = Vector2(int(cell.split(",")[0]), int(cell.split(",")[1]))
		var item = loadedDict.save_data2[1][cell]
		var json = JSON.new()
		json.parse(item)
		var node = json.get_data()
		if not node.has("source_id"):

			
			tileMap.set_cell(3, Vector2i(node["x"], node["y"]), -1)
			tileMap.set_cell(node["layer"], Vector2i(node["x"], node["y"]), -1)
			continue




		tileMap.set_cell(node["layer"], Vector2i(node["x"], node["y"]), node["source_id"],Vector2i( node["atlas_location_x"], node["atlas_location_y"] ))
		# Restore any other tile properties you saved previously.
		
	# Special 
	specialTiles = []
	specialTiles.append(Vector2i(3243,2343))

	for cell in loadedDict.save_data2[2].keys():

		#var cell_vector = Vector2(int(cell.split(",")[0]), int(cell.split(",")[1]))
		var item = loadedDict.save_data2[2][cell]
		var json = JSON.new()
		json.parse(item)
		var node = json.get_data()
		if not node.has("source_id"):

			
			tileMap.set_cell(3, Vector2i(node["x"], node["y"]), -1)
			tileMap.set_cell(node["layer"], Vector2i(node["x"], node["y"]), -1)
			continue
		#tileMap.set_cell(node["layer"], Vector2i(node["x"], node["y"]), -1)
		tileMap.set_cell(node["layer"], Vector2i(node["x"], node["y"]), -1)
		SetGameItemScene(Vector2i(node["x"], node["y"]), node["source_id"], Vector2i( 0,0 ))


