extends Node
class_name Resources

@export var items: Items

var resources: Dictionary = {}

# Called when the node enters the scene tree for the first time.
func _ready():
	resources[Types.Item.IronResource] = GameResource.new(Vector2i(4, 1), 4, Types.Item.IronResource, 1, false, "Iron", Vector2i.ZERO, false, Types.Item.IronOre,  Vector2i(8, 1))
	resources[Types.Item.Tree] =         GameResource.new(Vector2i(1, 0), 4, Types.Item.Tree,         1, false, "Tree", Vector2i.ZERO, false, Types.Item.Wood, Vector2i(4, 3))
	resources[Types.Item.StoneResource] = GameResource.new(Vector2i(2, 1), 4, Types.Item.StoneResource, 1, false, "Stone", Vector2i.ZERO, false, Types.Item.Stone, Vector2i.ZERO)
	resources[Types.Item.CoalResource] = GameResource.new(Vector2i(3, 1), 4,Types.Item.CoalResource, 1, false, "Coal", Vector2i.ZERO, false, Types.Item.CoalOre, Vector2i.ZERO)

func get_item_by_data(atlas_location, source_id):
	for key in resources.keys():
		if resources[key].atlas_location == atlas_location and resources[key].tile_source_id == source_id:
			return resources[key]
			
func Get(type: Types.Item) -> GameResource:
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
