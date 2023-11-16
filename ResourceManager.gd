extends Node
class_name ResourceManager

@export var player: Player
@export var itemManager: ItemManager
@export var tileMap: TileMap
@export var items: Items
@export var resources: Resources
@export var tileMapHandler: TileMapHandler

func _process(delta):
	pass

func AddRandomResource():
	var randomTile = tileMapHandler.get_random_tile()
	var randomResource = resources.get_random()
	
	if randomTile == null:
		return
	
	SetResource(randomTile, randomResource)

func SetResource(location, resource: GameResource):
	tileMapHandler.SetGameResource(location, resource.tile_source_id, resource.atlas_location)

	
func RemoveResource(location):
	tileMap.set_cell(1, location, -1)

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
		
	var direction = player.global_position - tileMap.map_to_local(nearestPos)
	var distance = direction.length()
	var activation_distance = 20
	
	if distance < activation_distance and distance > 0:
		var tile = tileMap.get_cell_atlas_coords (1, nearestPos)
		for key in resources.GetAllTypes():
			if resources.Get(key).atlas_location == tile:
				itemManager.AddItemToWorld( tileMap.map_to_local(nearestPos), items.Get(resources.Get(key).drop))
		
		RemoveResource(nearestPos)
	
func GetPlayerPosition():
	return tileMap.local_to_map(player.global_position)

