extends Node
class_name Resources

@export var items: Items

var resources: Dictionary = {}

# Early-game pacing lives here. Trees and stone are the common starter nodes that
# are quick to clear and pay little; coal and iron are rare, slow and worth the
# detour, which is what makes unlocking them read as progress rather than as more
# of the same. Weights are relative, so adding a resource does not dilute the rest
# evenly - iron stays rare no matter how many other nodes exist.
const TUNING = {
	Types.Item.Tree: {
		"xp": 1, "yield_min": 1, "yield_max": 2, "spawn_weight": 5.0,
		"secondary_drop": Types.Item.Food, "secondary_drop_chance": 0.2,
	},
	Types.Item.StoneResourceTest: {
		"xp": 1, "yield_min": 1, "yield_max": 2, "spawn_weight": 4.0,
	},
	Types.Item.StoneResource: {
		"xp": 1, "yield_min": 1, "yield_max": 2, "spawn_weight": 4.0,
	},
	Types.Item.CoalResource: {
		"xp": 3, "yield_min": 1, "yield_max": 2, "spawn_weight": 1.5,
	},
	Types.Item.IronResource: {
		"xp": 4, "yield_min": 1, "yield_max": 1, "spawn_weight": 1.0,
	},
	Types.Item.CopperResource: {
		"xp": 6, "yield_min": 1, "yield_max": 2, "spawn_weight": 0.8,
	},
	# The rarest node on the island, and the only one that also pays currency: gold
	# is what land costs, so a gold vein found while mining is the moment the map
	# gets bigger.
	Types.Item.GoldResource: {
		"xp": 9, "yield_min": 1, "yield_max": 1, "spawn_weight": 0.4,
		"secondary_drop": Types.Item.Coin, "secondary_drop_chance": 0.5,
	},
}


# Called when the node enters the scene tree for the first time.
func _ready():
	resources[Types.Item.IronResource] = GameResource.new(Vector2i(4, 1), 4, Types.Item.IronResource, 1, false, "Iron", Vector2i.ZERO, false, Types.Item.IronOre,  Vector2i(8, 1), GameSoundManager.SoundType.MINING)
	resources[Types.Item.Tree] =         GameResource.new(Vector2i(1, 0), 4, Types.Item.Tree,         1, false, "Tree", Vector2i.ZERO, false, Types.Item.Wood, Vector2i(4, 3), GameSoundManager.SoundType.WOOD_PLACE)
	resources[Types.Item.StoneResource] = GameResource.new(Vector2i(2, 1), 4, Types.Item.StoneResource, 1, false, "Stone", Vector2i.ZERO, false, Types.Item.Stone, Vector2i(3,5), GameSoundManager.SoundType.MINING)
	resources[Types.Item.StoneResourceTest] = GameResource.new(Vector2i(0, 0), 9, Types.Item.StoneResourceTest, 1, true, "Stone", Vector2i.ZERO, true, Types.Item.Stone, Vector2i.ZERO, GameSoundManager.SoundType.MINING)
	resources[Types.Item.StoneResourceTest].is_scene_tile = true
	resources[Types.Item.CoalResource] = GameResource.new(Vector2i(3, 1), 4,Types.Item.CoalResource, 1, false, "Coal", Vector2i.ZERO, false, Types.Item.CoalOre, Vector2i.ZERO, GameSoundManager.SoundType.MINING)

	# Placeholder-art tiers on tileset source 10. Several lookups in main.gd match a
	# resource by atlas coordinate alone, so these coordinates must stay unique
	# across ALL resources, not just within their own source.
	resources[Types.Item.CopperResource] = GameResource.new(Vector2i(0, 3), 10, Types.Item.CopperResource, 1, false, "Copper", Vector2i.ZERO, false, Types.Item.CopperOre, Vector2i(2, 3), GameSoundManager.SoundType.MINING)
	resources[Types.Item.GoldResource] = GameResource.new(Vector2i(1, 3), 10, Types.Item.GoldResource, 1, false, "Gold", Vector2i.ZERO, false, Types.Item.GoldOre, Vector2i(3, 3), GameSoundManager.SoundType.MINING)

	_apply_tuning()


func _apply_tuning():
	for type in TUNING:
		var resource: GameResource = resources.get(type)
		if resource == null:
			push_warning("Resources: tuning entry for unknown resource type %s" % type)
			continue
		for property in TUNING[type]:
			resource.set(property, TUNING[type][property])


func get_resource_by_data(atlas_location, source_id):
	for key in resources.keys():
		if resources[key].atlas_location == atlas_location and resources[key].tile_source_id == source_id:
			return resources[key]
			
func get_item_or_resource(atlas_location, source_id) -> GameItem:
	for key in resources.keys():
		var resource = resources.get(key)
		if resource.atlas_location == atlas_location and resource.tile_source_id == source_id:
			return resource
			
	for key in items.item_list.keys():
		var item = items.item_list.get(key)
		if item.atlas_location == atlas_location and item.tile_source_id == source_id:
			return item
			
	return null
	
func get_item_or_resource_by_type(type: Types.Item) -> GameItem:
	for key in resources.keys():
		var resource = resources.get(key)
		if resource.type == type:
			return resource
			
	for key in items.item_list.keys():
		var item = items.item_list.get(key)
		if item.type == type:
			return item
			
	return null
			
func Get(type: Types.Item) -> GameResource:
	return resources[type]
	
func GetAllTypes():
	var types = []
	for key in resources:
		types.append(key)
	return types
	


func get_random_key() -> Variant:
	var keys = resources.keys()
	if keys.size() == 0:
		return null  # Return null or handle the empty dictionary case as appropriate for your game
	var random_index = randi() % keys.size()
	return keys[random_index]
