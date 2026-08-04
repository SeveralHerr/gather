extends Node
class_name Resources

@export var items: Items

var resources: Dictionary = {}

# Early-game pacing lives here. Trees and stone are the common starter nodes that
# are quick to clear and pay little; coal and copper are the scarce ones a starting
# player can still find, and iron and gold do not appear at all until their skill is
# bought, which is what makes those two read as progress rather than as more of the
# same. Weights are relative, so adding a resource does not dilute the rest evenly -
# gold stays rare no matter how many other nodes exist.
const TUNING = {
	# No secondary drop any more. Trees used to hand out Food at 0.2, which made the
	# potion-bottle icon at tiles.png (15,0) something a new player tripped over while
	# chopping — the strongest single heal in the early game, from the most common node in
	# the world. Food is now a 4% ENEMY drop (EnemyRegistry.TYPES), so healing is bought with
	# risk, and the berry bush below is what pays out for walking around picking things.
	Types.Item.Tree: {
		"xp": 1, "yield_min": 1, "yield_max": 2, "spawn_weight": 5.0,
	},
	# Weighted just above coal: a bush should be a familiar sight on the walk between trees
	# without competing with the two building materials. This is the entry that moved
	# MAINLAND_ORE_SHARE — see the note on that constant.
	Types.Item.BerryBush: {
		"xp": 1, "yield_min": 1, "yield_max": 2, "spawn_weight": 1.5,
	},
	Types.Item.StoneResourceTest: {
		"xp": 1, "yield_min": 1, "yield_max": 2, "spawn_weight": 4.0,
	},
	Types.Item.StoneResource: {
		"xp": 1, "yield_min": 1, "yield_max": 2, "spawn_weight": 4.0,
	},
	# Every ore node pays the same 1 xp as a tree or a stone. Rarity used to be priced
	# in xp as well (3/4/6/9), which made a copper vein worth six trees and turned the
	# mining tier into the fastest way to level rather than the slowest way to get
	# materials. The ladder is still there — it is expressed in spawn_weight, in what
	# the drop is worth to a recipe, and in gold's coins. XP is no longer part of it.
	#
	# Every ore weight below is 0.7x what it was: ore was asked to turn up ~30% less
	# often on ordinary ground. The cut is on the WEIGHTS, and weight is relative, so
	# it does not land as a 30% cut to what the player sees — the slack goes to trees
	# and stone, and ore's share of a mainland roll falls from ~16.1% to ~11.9%, i.e.
	# about a quarter fewer veins. MAINLAND_ORE_SHARE below is that number, held by a
	# test, because it is the thing being tuned and it is not readable off this table.
	#
	# The island overrides in IslandManager.ISLANDS state their own ore weights and are
	# untouched by this, which is the point: mining on the mainland got thinner and the
	# ore island stayed the place worth crossing the water for.
	Types.Item.CoalResource: {
		"xp": 1, "yield_min": 1, "yield_max": 2, "spawn_weight": 1.05,
	},
	# Rarity tracks the crafting tier: copper is the ore the furnace sees first and the
	# one that spawns unlocked, so it is the commoner of the two. These weights used to
	# be the other way round, which made the lower tier the scarcer one.
	Types.Item.CopperResource: {
		"xp": 1, "yield_min": 1, "yield_max": 2, "spawn_weight": 0.7,
	},
	Types.Item.IronResource: {
		"xp": 1, "yield_min": 1, "yield_max": 1, "spawn_weight": 0.56,
	},
	# The rarest node on the island, and the only one that also pays currency: gold
	# is what land costs, so a gold vein found while mining is the moment the map
	# gets bigger. That payout is the coins, not the xp.
	Types.Item.GoldResource: {
		"xp": 1, "yield_min": 1, "yield_max": 1, "spawn_weight": 0.28,
		"secondary_drop": Types.Item.Coin, "secondary_drop_chance": 0.5,
	},
}

## Which types count as ore for the mainland-scarcity guard below. Stone is deliberately
## not one of them: it is a building material the player is meant to trip over, and it is
## what the ore cut hands its slack to.
const ORE_TYPES := [
	Types.Item.CoalResource,
	Types.Item.CopperResource,
	Types.Item.IronResource,
	Types.Item.GoldResource,
]

## Ore's share of an ordinary mainland spawn roll once the starting set is unlocked, i.e.
## coal and copper against trees and the two stones.
##
## Stated as a number because it is the thing the weights above are for, and because no
## reader can get it from them: weight is relative and stone is two entries, so "coal 1.05"
## says nothing on its own about how often the player finds coal. A test samples the real
## roll against this, so anyone who nudges a weight finds out what they did to the mainland.
##
## It was 0.119 before the berry bush existed. Adding a sixth starting resource at weight 1.5
## diluted every other share by the same proportion — ore included — and this number is
## restated rather than defended: the ore weights themselves are untouched, so the mining
## ladder still reads exactly as it did relative to stone and trees, and what actually changed
## is that there is now one more thing on the ground. Scaling the four ore weights up to hold
## 0.119 would have been the alternative and was not taken, because it would mean every future
## resource added to the world has to pay ore a tax to exist.
const MAINLAND_ORE_SHARE := 0.108
const MAINLAND_ORE_SHARE_TOLERANCE := 0.02


# Called when the node enters the scene tree for the first time.
func _ready():
	resources[Types.Item.IronResource] = GameResource.new(Vector2i(4, 1), 4, Types.Item.IronResource, 1, false, "Iron", Vector2i.ZERO, false, Types.Item.IronOre,  Vector2i(8, 1), GameSoundManager.SoundType.MINING)
	resources[Types.Item.Tree] =         GameResource.new(Vector2i(1, 0), 4, Types.Item.Tree,         1, false, "Tree", Vector2i.ZERO, false, Types.Item.Wood, Vector2i(4, 3), GameSoundManager.SoundType.WOOD_PLACE)
	resources[Types.Item.StoneResource] = GameResource.new(Vector2i(2, 1), 4, Types.Item.StoneResource, 1, false, "Stone", Vector2i.ZERO, false, Types.Item.Stone, Vector2i(3,5), GameSoundManager.SoundType.MINING)
	resources[Types.Item.StoneResourceTest] = GameResource.new(Vector2i(0, 0), 9, Types.Item.StoneResourceTest, 1, true, "Stone", Vector2i.ZERO, true, Types.Item.Stone, Vector2i.ZERO, GameSoundManager.SoundType.MINING)
	resources[Types.Item.StoneResourceTest].is_scene_tile = true
	resources[Types.Item.CoalResource] = GameResource.new(Vector2i(3, 1), 4,Types.Item.CoalResource, 1, false, "Coal", Vector2i.ZERO, false, Types.Item.CoalOre, Vector2i.ZERO, GameSoundManager.SoundType.MINING)

	# A scene tile, like StoneResourceTest, because it is the only resource that carries state
	# between gathers: which of its two states it is in, and how far through refruiting. The
	# atlas coordinate is (0,0) because source 14 is a scenes collection and the cell only ever
	# names the scene — the art the player sees is chosen by the node (world/resource_nodes/
	# berry_bush.gd), not by the cell.
	#
	# `drop` is Berry, which is what PICKING a fruiting bush pays. Uprooting a picked one pays
	# the bush itself instead, and that is ResourceManager2's branch to make, not a second
	# field here: one resource, two gathers.
	resources[Types.Item.BerryBush] = GameResource.new(Vector2i(0, 0), GameItem.BERRY_BUSH_SOURCE_ID, Types.Item.BerryBush, 1, true, "Berry Bush", Vector2i.ZERO, true, Types.Item.Berry, Vector2i.ZERO, GameSoundManager.SoundType.WOOD_GATHER)
	resources[Types.Item.BerryBush].is_scene_tile = true

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
