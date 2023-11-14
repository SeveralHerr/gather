extends Node
class_name Resources

@export var items: Items

var resources: Dictionary = {}

# Called when the node enters the scene tree for the first time.
func _ready():
	resources[GameResource.Type.Tree] = GameResource.new(Vector2i(1, 0), 4, items.Get(GameItem.Type.Wood), GameResource.Type.Tree, Vector2i(4, 3))
	resources[GameResource.Type.Stone] = GameResource.new(Vector2i(2, 1), 4, items.Get(GameItem.Type.Stone), GameResource.Type.Stone)
	resources[GameResource.Type.Iron] = GameResource.new(Vector2i(4, 1), 4, items.Get(GameItem.Type.IronOre), GameResource.Type.Iron, Vector2i(8, 1))
	resources[GameResource.Type.Coal] = GameResource.new(Vector2i(3, 1), 4, items.Get(GameItem.Type.CoalOre), GameResource.Type.Coal)

func get_item_by_data(atlas_location, source_id):
	for key in resources.keys():
		if resources[key].atlas_location == atlas_location and resources[key].tile_source_id == source_id:
			return resources[key]
			
func Get(type: GameResource.Type) -> GameResource:
	return resources[type]
	
func GetAllTypes():
	var types = []
	for key in resources:
		types.append(key)
	return types
	
func get_random():
	var key = get_random_key()
	return resources[key]

func get_random_key() -> Variant:
	var keys = resources.keys()
	if keys.size() == 0:
		return null  # Return null or handle the empty dictionary case as appropriate for your game
	var random_index = randi() % keys.size()
	return keys[random_index]
