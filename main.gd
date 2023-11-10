extends Node
class_name TileMapHandler
var resources = {}
@export var player: Player
@export var itemManager: ItemManager
@export var tileMap: TileMap
@export var items: Items

# Called when the node enters the scene tree for the first time.
func _ready():
	AddRandomResource()

# Called every frame. 'delta' is the elapsed time since the previous frame.
func _process(delta):
	GetPlayerPosition()

func SetResource(location, resource):
	tileMap.set_cell(1, location, 0, resource)
	
func RemoveResource(location):
	tileMap.set_cell(1, location, -1)
	
func AddRandomResource():
	var randomTile = get_random_tile()
	var randomResource = GetRandomResource()
	
	SetResource(randomTile, randomResource.atlas_location)
	
func GetRandomResource():
	if items.items.size() == 0:
		return
	var random_index = randi() % items.items.size()
	print(random_index)
	return items.items[random_index]

func get_random_tile():
	# Get the used rectangle, which includes the area where tiles are placed
	var used_rect = tileMap.get_used_rect()
	
	# Generate a random position within the used rectangle
	var random_x = randi() % used_rect.size.x + used_rect.position.x
	var random_y = randi() % used_rect.size.y + used_rect.position.y

	# Get the tile index at the random position
	var tile_index = tileMap.get_cell_tile_data(1, Vector2(random_x, random_y))

	# Optionally, if you want to keep trying random positions until you find a non-empty tile
	while tile_index:
		random_x = randi() % used_rect.size.x + used_rect.position.x
		random_y = randi() % used_rect.size.y + used_rect.position.y
		tile_index = tileMap.get_cell_tile_data(1, Vector2(random_x, random_y))

	return Vector2(random_x, random_y)

func RemoveNearestResourceToPlayer():
	var neighbors = [Vector2i.UP, Vector2i.DOWN, Vector2i.LEFT, Vector2i.RIGHT, Vector2i.UP + Vector2i.LEFT, Vector2i.UP + Vector2i.RIGHT, Vector2i.DOWN + Vector2i.LEFT, Vector2i.DOWN + Vector2i.RIGHT, Vector2i.ZERO]
	var nearestDistance = 1000000
	var nearestPos = Vector2i(-1, -1)

	for neighbor in neighbors:
		var tilePos = GetPlayerPosition() + neighbor
		var tile = tileMap.get_cell_atlas_coords (1, tilePos)
		if tile == Vector2i(-1,-1):
			continue
		
		var direction = player.global_position - tileMap.map_to_local(tilePos)
		var distance = direction.length()
		if distance < nearestDistance:
			nearestDistance = distance
			nearestPos = tilePos
		
	if nearestPos == Vector2i(-1,-1):
		return
	var direction = player.global_position - tileMap.map_to_local(nearestPos)
	var distance = direction.length()
	var activation_distance = 20
	
	if distance < activation_distance and distance > 0:
		var tile = tileMap.get_cell_atlas_coords (1, nearestPos)
		for item in items.items:
			if item.atlas_location == tile:
				itemManager.AddItemToWorld( tileMap.map_to_local(nearestPos), item)
		
		RemoveResource(nearestPos)
	
func GetPlayerPosition():
	return tileMap.local_to_map(player.global_position)

