extends Node
class_name TileMapHandler

signal resource_found(resource, location)  

@export var player: Player
@export var tileMap: TileMap
@export var items: Items
@export var specialTiles = []
@export var resource_manager: ResourceManager2
@export var resources: Resources
@export var sound_manager: SoundManager
@onready var input_manager = $InputManager
@onready var save_load: SaveLoad = $Node2D/Player/Camera2D/UI/SaveLoad
@onready var destroy_manager = $DestroyManager
var chest = preload("res://world/tile_scenes/chest.tscn")

## Every autotiling wall. A placed wall is identified by its atlas SOURCE plus the
## rect its 47-tile blob occupies on that sheet - neither half is sufficient alone.
## The source alone is not, because the wood blob shares tiles.png with every other
## hand-drawn tile; the rect alone is not, because the generated stone sheet starts
## its blob at (0, 0) and those coordinates are already stone, plank and wood-floor
## on the hand-drawn sheet.
##
## `base` is the blob's top-left cell, which is what a whole run is reset to before
## set_cells_terrain_connect recomputes the joins, and it is also the coordinate the
## matching GameItem is registered under in items.gd. `terrain` is the index in
## terrain set 0, and it is per wall type on purpose: two terrains means a stone wall
## meeting a wood wall reads as two walls butting together rather than one blended run.
const WALL_TYPES := [
	{
		"item": Types.Item.WoodWall,
		"source": 4,
		"rect": Rect2i(0, 7, 12, 5),
		"terrain": 0,
		"base": Vector2i(0, 11),
	},
	{
		"item": Types.Item.StoneWall,
		"source": GameItem.STONE_BUILD_SOURCE_ID,
		"rect": Rect2i(0, 0, 12, 5),
		"terrain": 2,
		"base": Vector2i(0, 4),
	},
]

## Placed wall cells per wall type, keyed by Types.Item. Filled lazily by
## _wall_cells_for so a wall type that has never been built carries no entry.
var wall_cells := {}

var ground_tiles_min = Vector2(0,15)
var ground_tiles_max = Vector2(11,18)

var radius = 10
var noise_scale = 1
var noise_threshold = 0.0
var noise = FastNoiseLite.new() # Instance of OpenSimplexNoise
var tile_index = 0 # You should set this to the appropriate tile index

## Owns the island radius from the moment land becomes purchasable. Created in
## _ready() rather than placed in main.tscn.
var land_manager: LandManager

var late_load = false

var disableSetTile = false
@export var save_data2 = {}

var crack = preload("res://assets/materials/crack_material.tres")
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
	
	var tile_grid = tileMap.get_used_cells(0)
	
	for cell in tile_grid:
		tileMap.set_cell(0, cell, -1)
	#noise.set_frequency(0.5)	
	noise.set_seed(randi())
	var lands := land_cells_for_radius(radius)
	tileMap.set_cells_terrain_connect(0, lands, 0, 1)

	PlayerManager.player.position = tileMap.map_to_local(lands[0])
	PlayerManager.player.set_spawn_position(PlayerManager.player.position)

	_setup_land_purchase()


## The land cells of an island of `island_radius`, straight out of the noise field.
## Deterministic for a given seed, so the same call at a larger radius returns a
## superset of the smaller one — which is what lets the island grow without the
## coastline the player already owns changing shape.
func land_cells_for_radius(island_radius: int) -> Array[Vector2i]:
	var lands: Array[Vector2i] = []
	for x in range(-island_radius, island_radius + 1):
		for y in range(-island_radius, island_radius + 1):
			if Vector2(x, y).length() > island_radius:
				continue
			if noise.get_noise_2d(x * noise_scale, y * noise_scale) < noise_threshold:
				lands.append(Vector2i(x, y))
	return lands


## Grows the island out to `new_radius` and returns how many land cells that
## revealed. Non-destructive, and the two things that make it so are worth
## spelling out:
##
##  - The noise instance and its seed are left alone. Reseeding would give the
##    already-owned half of the island a different shape, stranding buildings in
##    the sea.
##  - Only layer 0 is written. Resources, walls and buildings live on layers 1
##    and 2 and are never touched.
##
## The *whole* land set is handed to set_cells_terrain_connect, not just the new
## ring: the old coastline tiles need to be re-solved as interior now that there
## is land beyond them, and that only happens if they are in the set.
func expand_island(new_radius: int) -> int:
	if new_radius <= radius:
		return 0

	var before := land_cells_for_radius(radius).size()
	radius = new_radius

	var lands := land_cells_for_radius(radius)
	tileMap.set_cells_terrain_connect(0, lands, 0, 1)

	return lands.size() - before


## The seed the island's shape comes out of. randomize()d per session, so it has
## to be saved alongside the land purchases: re-expanding a loaded island against
## a fresh seed would grow a coastline that has nothing to do with the one the
## player bought.
func island_seed() -> int:
	return noise.seed


func set_island_seed(new_seed: int) -> void:
	noise.set_seed(new_seed)


## A bought parcel is stocked immediately rather than trickling in over the next ten
## minutes — the land is what was paid for, and empty grass does not read as a purchase.
func _on_land_purchased(_new_radius: int, _tiles_added: int) -> void:
	resource_manager.seed_island()


## The land economy and its panel. Both are created here rather than placed in
## main.tscn so the scene file stays untouched; the panel goes in the UI2
## CanvasLayer (screen space) and never under Player/Camera2D/UI, which is world
## space at 0.23 scale for the diegetic HUD.
func _setup_land_purchase() -> void:
	land_manager = LandManager.new()
	land_manager.name = "LandManager"
	land_manager.tile_map_handler = self
	add_child(land_manager)

	# Stock the island the player is standing on, and every parcel they buy after it.
	# ResourceManager2's own _ready() runs before this one — children are readied
	# before their parent — so at that point there is no land to put anything on yet.
	resource_manager.seed_island()
	land_manager.land_purchased.connect(_on_land_purchased)

	var ui2 := get_node_or_null("UI2")
	if ui2 == null:
		push_warning("TileMapHandler: no UI2 CanvasLayer, the land panel has nowhere to live")
		return

	var panel := LandPurchaseUi.new()
	panel.name = "LandPurchaseUI"
	panel.land_manager = land_manager
	panel.tile_map_handler = self
	panel.input_manager = input_manager
	ui2.add_child(panel)


# Called every frame. 'delta' is the elapsed time since the previous frame.
func _process(_delta):
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

	
func _on_destroy_removing(location: Vector2i, _item: GameItem):
	# Add highlight
	tileMap.set_cell(3, tileMap.local_to_map(location), 4, Vector2i(7, 1))
	
	#tileMap.set_tile(tileMap.local_to_map(location),item.tile_source_id, item.atlas_location, item.layer, item.is_scene_tile)
	
func _on_destroy_added(location: Vector2i, item: GameItem):
	set_tile(location,item.tile_source_id, item.atlas_location, item.layer, item.is_scene_tile)

func _on_destroy_removed(location: Vector2i, item: GameItem):
	tileMap.set_cell(item.layer,tileMap.local_to_map(location), -1)
	tileMap.set_cell(3, tileMap.local_to_map(location), -1)

	var wall := wall_type_at(item.atlas_location, item.tile_source_id)
	if wall.is_empty():
		return

	var cells: Array = _wall_cells_for(wall)
	var index = cells.find(tileMap.local_to_map(location))
	if index != -1:
		cells.remove_at(index)

	# Only the type that lost a cell needs re-solving; the other wall's run is on its
	# own terrain and cannot have changed shape.
	reconnect_walls(wall)


## The wall type a tile belongs to, or an empty Dictionary. Both halves of the match
## matter - see WALL_TYPES. Empty rather than null so callers can subscript the result
## without GDScript's analyser collapsing the return type to null.
func wall_type_at(atlas_location: Vector2i, source_id: int) -> Dictionary:
	for wall in WALL_TYPES:
		if wall["source"] == source_id and wall["rect"].has_point(atlas_location):
			return wall
	return {}


func _wall_cells_for(wall: Dictionary) -> Array:
	if not wall_cells.has(wall["item"]):
		wall_cells[wall["item"]] = []
	return wall_cells[wall["item"]]


## Resets one wall type's run to its blob's top-left cell and lets the terrain solver
## recompute every join. Both steps are needed: set_cells_terrain_connect only looks at
## which cells are in the run, so a cell still showing a previously-solved corner keeps
## drawing that corner if it is not flattened back to `base` first.
func reconnect_walls(wall: Dictionary) -> void:
	var cells: Array = _wall_cells_for(wall)
	for tile in cells:
		tileMap.set_cell(1, tile, wall["source"], wall["base"])
	tileMap.set_cells_terrain_connect(1, cells, 0, wall["terrain"], false)


func _on_destroy_removing_stop(location: Vector2i, _item: GameItem):
	# Remove highlight
	tileMap.set_cell(3, tileMap.local_to_map(location), -1)
	#set_tile(location,item.tile_source_id, item.atlas_location, item.layer, item.is_scene_tile)
	
	
func _on_mouse_left(isUiOpen: bool):
	disableSetTile = isUiOpen

func _on_resource_added(location: Vector2i, resource: GameResource):
	set_tile(location,resource.tile_source_id, resource.atlas_location, resource.layer, resource.is_scene_tile)

## Every ore node breaks with the same stone crack; only tree and the scene-based
## nodes sound different.
const STONE_SOUNDED_RESOURCES := [
	Types.Item.StoneResource,
	Types.Item.CoalResource,
	Types.Item.IronResource,
	Types.Item.CopperResource,
	Types.Item.GoldResource,
]

func _on_resource_removed(location: Vector2i, resource: GameResource):
	if resource.type in STONE_SOUNDED_RESOURCES:
		sound_manager.play_sound(SoundManager.SoundType.STONE)

	clear_tile(tileMap.local_to_map(location))

func _on_resource_removing(location: Vector2i, resource: GameResource):
	# Add highlight
	tileMap.set_cell(3, tileMap.local_to_map(location), 4, Vector2i(7, 1))

	# The mid-gather frame lives on the same sheet as the node itself, so the source
	# id has to come from the resource. It used to be hardcoded to 4, which drew
	# whatever happened to sit at those coordinates on the hand-drawn sheet for any
	# resource registered against another source.
	if resource.gathering_atlas_location != Vector2i.ZERO:
		tileMap.set_cell(1, tileMap.local_to_map(location), resource.tile_source_id, resource.gathering_atlas_location)

func _on_resource_removing_stop(location: Vector2i, resource: GameResource):
	# Remove highlight
	var cell := tileMap.local_to_map(location)
	tileMap.set_cell(3, cell, -1)

	if resource.gathering_atlas_location != Vector2i.ZERO:
		# Only put the idle frame back if the cell is still showing the mid-gather one.
		# This used to write unconditionally, so a stop that arrived for a location whose
		# cell had already been cleared *recreated* the resource tile — a node that looked
		# alive with nothing behind it.
		if tileMap.get_cell_atlas_coords(1, cell) == resource.gathering_atlas_location:
			tileMap.set_cell(1, cell, resource.tile_source_id, resource.atlas_location)

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

	var wall := wall_type_at(atlas_location, tile_source_id)
	if not wall.is_empty():
		var cells: Array = _wall_cells_for(wall)
		if not cells.has(location):
			cells.append(location)
		reconnect_walls(wall)

func is_wall_tile(atlas_location, source_id: int) -> bool:
	return not wall_type_at(atlas_location, source_id).is_empty()


## Things built out of stone land with the stone sound rather than the wood one, which
## is the only place the two building sets differ in behaviour rather than in art.
const STONE_SOUNDED_BUILDS := [Types.Item.StoneWall, Types.Item.StoneFloor]

func play_audio(_location: Vector2i, tile_source_id: int, atlas_location: Vector2i, _layer: int, _is_scene: bool = false):
	var item = items.get_item_by_data(atlas_location, tile_source_id)

	var wall := wall_type_at(atlas_location, tile_source_id)
	if not wall.is_empty():
		sound_manager.play_sound(
			sound_manager.SoundType.STONE if wall["item"] in STONE_SOUNDED_BUILDS
			else sound_manager.SoundType.WOOD_PLACE
		)
	elif item and item.type in STONE_SOUNDED_BUILDS:
		sound_manager.play_sound(sound_manager.SoundType.STONE)
	elif item and ( item.type == Types.Item.Chest or item.type == Types.Item.WoodDoor or item.type == Types.Item.Sawmill or item.type == Types.Item.WoodFloor):
			sound_manager.play_sound(sound_manager.SoundType.WOOD_PLACE)
	
func is_occupied(tilePos: Vector2i, include_resources = false, is_wall: bool = false)-> bool:
	var occupied = false
	
	if is_wall == true:
		return false
	
	var tile = tileMap.get_cell_tile_data(1, tilePos)
	if tile != null:
		occupied = true
		
	tile = tileMap.get_cell_tile_data(2, tilePos)
	if tile != null and include_resources == true:
		occupied = true
		
	# Check if trying to spawn on anything that is not grass
	if tileMap.get_cell_atlas_coords(0, tilePos) != GRASS_ATLAS:
		occupied = true
	
	
	var atlas_location = tileMap.get_cell_atlas_coords(1, tilePos)
	var source_id = tileMap.get_cell_source_id (1, tilePos)
	var item = resources.get_item_or_resource(atlas_location, source_id)
	
	if item != null and item.is_scene_tile:
		occupied = true
			

	return occupied
		
func RemoveResource(location):
	tileMap.set_cell(1, location, -1)

## Live gatherable nodes on the island broken down by resource name, covering both
## tile-based resources and the scene-based ones parented to the tilemap.
func resource_node_census() -> Dictionary:
	var atlas_to_name = {}
	for key in resources.GetAllTypes():
		var resource = resources.Get(key)
		if not resource.is_scene_tile:
			atlas_to_name[resource.atlas_location] = resource.name

	var census = {}
	for cell in tileMap.get_used_cells(1):
		var atlas = tileMap.get_cell_atlas_coords(1, cell)
		if atlas_to_name.has(atlas):
			var resource_name = atlas_to_name[atlas]
			census[resource_name] = census.get(resource_name, 0) + 1

	for node in tileMap.get_children():
		if node is GameSceneResource:
			var resource = resources.get_item_or_resource_by_type(node.resource_type)
			var resource_name = resource.name if resource else "Unknown"
			census[resource_name] = census.get(resource_name, 0) + 1

	return census


## Plain grass. This exact tile is what "walkable, buildable land" means everywhere
## in the project — spawn placement, occupancy and the island size all key off it.
const GRASS_ATLAS := Vector2i(9, 17)


## Every plain-grass ground cell on the island, in tilemap coordinates.
func land_tiles() -> Array:
	var tiles := []
	for cell in tileMap.get_used_cells(0):
		if tileMap.get_cell_atlas_coords(0, cell) == GRASS_ATLAS:
			tiles.append(cell)
	return tiles


## How big the island is right now. Grows as land is bought, which is what the
## resource and enemy population ceilings scale against.
func count_land_tiles() -> int:
	return land_tiles().size()


## Total live resource nodes. Used to cap spawning.
func count_resource_nodes() -> int:
	var census = resource_node_census()
	var total = 0
	for resource_name in census:
		total += census[resource_name]
	return total

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
		
		var dir = player.global_position - tileMap.map_to_local(tilePos)
		var dist = dir.length()
		if dist < nearestDistance:
			nearestDistance = dist
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
		
		if tile_atlas == Vector2i(-1,-1):
			continue

		var dir = player.global_position - tileMap.map_to_local(tilePos)
		var dist = dir.length()
		if dist < nearestDistance:
			nearestDistance = dist
			nearestPos = tilePos

	if nearestPos == null:
		return
	
	var direction = location - tileMap.map_to_local(nearestPos)
	var distance = direction.length()
	var activation_distance = 20
	
	if distance < activation_distance and distance > 0:
		var tile_atlas = tileMap.get_cell_atlas_coords(1, nearestPos)
		var tile_source_id = tileMap.get_cell_source_id(1, nearestPos)

		# A placed wall is showing whichever of its 47 cells the terrain solver chose,
		# and only the blob's top-left cell is registered as an item - so normalise
		# back to it before looking the item up.
		var wall := wall_type_at(tile_atlas, tile_source_id)
		if not wall.is_empty():
			tile_atlas = wall["base"]

		for key in items.get_all_types():
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
		
		var dir = player.global_position - tileMap.map_to_local(tilePos)
		var dist = dir.length()
		if dist < nearestDistance:
			nearestDistance = dist
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
				return { "resource": resources.Get(key),  "location": tileMap.map_to_local(nearestPos), "tile_data": tileMap.get_cell_tile_data(resources.Get(key).layer, nearestPos ) }

func get_nearest_scene_tile():
	var nearestDistance = 1000000
	var nearest = null
	var nodes = tileMap.get_children()
	for i in nodes.size():
		if nodes[i] is GameSceneResource:
					
			var dir = player.global_position - nodes[i].position
			var dist = dir.length()
			if dist < nearestDistance:
					nearestDistance = dist
					nearest = nodes[i]
					
	return nearest

func place_auto_tile( atlas_location):
	# Set the tile at the specified cell position.
	tileMap.set_cell(3, Vector2i(1, 1), 4, atlas_location) 
	tileMap.set_cell(3, Vector2i(1, 2), 4, atlas_location ) 
	tileMap.set_cell(3, Vector2i(0, 2), 4, atlas_location) 
	# Update the bitmasks to apply auto-tiling rules.
	#tileMap.bitma(cell_position - Vector2(1, 1), cell_position + Vector2(1, 1))
	tileMap.set_cells_terrain_connect(3, _wall_cells_for(WALL_TYPES[0]), 0, WALL_TYPES[0]["terrain"])


func rain():
	var amt = 19
	for i in amt:
		var tile = get_random_tile()
		tileMap.set_cell(1, tile, 7, Vector2(0,0))
		#get_tree().create_timer(0.1).timeout

func get_random_tile():
	# Get the used rectangle, which includes the area where tiles are placed
	var used_tiles = land_tiles()

	if not used_tiles:
		return
	
	var max_retries = 100
	var try = 1


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
			var wall := wall_type_at(atlas_location, source_id)
			if not wall.is_empty():
				# Saved as the wall type itself, never as the solved cell: the joins are
				# recomputed from the run on load, so which of the 47 it happens to be
				# showing right now is not worth persisting.
				item = items.get_item(wall["item"])
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
	wall_cells.clear()
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

		if item.type == Types.Item.BoneTurret:
			pass
		set_tile(location, item.tile_source_id, item.atlas_location, item.layer,item.is_scene_tile)
		tileMap.set_cells_terrain_connect(0, ground_tiles, 0, 1)
	late_load = true

