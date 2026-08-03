extends Node
class_name Items

var item_list: Dictionary = {}

# Called when the node enters the scene tree for the first time.
func _ready():
	add_to_group("Items")
	item_list[Types.Item.Stone] = GameItem.new(Vector2i(1, 2), 4, Types.Item.Stone, 1, false, "Stone", Vector2i.ZERO)
	item_list[Types.Item.Wood] = GameItem.new(Vector2i(2, 2), 4, Types.Item.Wood, 1, false, "Wood", Vector2i.ZERO)
	item_list[Types.Item.Plank] = GameItem.new(Vector2i(3, 2), 4, Types.Item.Plank, 1, false, "Plank", Vector2i.ZERO)
	item_list[Types.Item.Sawmill] = GameItemPlaceable.new(Vector2i(0, 0), 2, Types.Item.Sawmill, 1, true, "Sawmill", Vector2i(0, 2), true)
	item_list[Types.Item.WoodFloor] = GameItemFloor.new(Vector2i(4, 2), 4, Types.Item.WoodFloor, 2, true, "Wood Floor", Vector2i.ZERO)
	item_list[Types.Item.CoalOre] = GameItem.new(Vector2i(5, 2), 4, Types.Item.CoalOre, 1, false, "Coal Ore", Vector2i.ZERO)
	item_list[Types.Item.IronOre] = GameItem.new(Vector2i(6, 2), 4, Types.Item.IronOre, 1, false, "Iron Ore", Vector2i.ZERO)
	item_list[Types.Item.IronBar] = GameItem.new(Vector2i(7, 2), 4, Types.Item.IronBar, 1, false, "Iron Bar", Vector2i.ZERO)
	item_list[Types.Item.WoodWall] = GameItemWall2.new(Vector2i(0, 11), 4, Types.Item.WoodWall, 1, true, "Wood Wall", Vector2i.ZERO)
	item_list[Types.Item.Furnace] = GameItemPlaceable.new(Vector2i(0, 0), 5, Types.Item.Furnace, 1, true, "Furnace", Vector2i(0,5), true)
	item_list[Types.Item.WoodDoor] = GameItemPlaceable.new(Vector2i(0,0), 1, Types.Item.WoodDoor, 1, true, "Wood Door", Vector2i(0, 13), true)
	item_list[Types.Item.Grass] = GameItem.new(Vector2i(0,0), 4, Types.Item.Grass, 0, false, "Grass", Vector2i.ZERO)
	item_list[Types.Item.Ground] = GameItem.new(Vector2i(0,18), 4, Types.Item.Ground, 0, false, "Ground", Vector2i.ZERO)
	item_list[Types.Item.Water] = GameItem.new(Vector2i(15,5), 4, Types.Item.Water, 0, false, "Water", Vector2i.ZERO)
	item_list[Types.Item.Chest] = GameItemPlaceable.new(Vector2i(0,0), 8, Types.Item.Chest, 1, true, "Chest", Vector2i(11,2), true)
	item_list[Types.Item.Bone] = GameItem.new(Vector2i(11,1), 4, Types.Item.Bone, 1, false, "Bone", Vector2i.ZERO, false)
	item_list[Types.Item.BoneTurret] = GameItemPlaceable.new(Vector2i(0,0), 6, Types.Item.BoneTurret, 1, true, "Bone Turret", Vector2i(19,3), true)
	# Scene tile on its own scenes-collection source (12), same shape as the turret.
	# The icon is the unassembled base at tiles.png (20,2); the four chop frames sit
	# next to it at (21,2)..(24,2) and are only ever drawn by the scene itself.
	item_list[Types.Item.BoneWorker] = GameItemPlaceable.new(Vector2i(0,0), 12, Types.Item.BoneWorker, 1, true, "Bone Worker", Vector2i(20,2), true)
	# The grey sibling: same scene script, harvest_type overridden to StoneResource, and its
	# own scenes-collection source because a scene tile is keyed by source id. Icon is the
	# grey unassembled base at (22,3).
	item_list[Types.Item.StoneWorker] = GameItemPlaceable.new(Vector2i(0,0), 13, Types.Item.StoneWorker, 1, true, "Stone Worker", Vector2i(22,3), true)
	item_list[Types.Item.Net] = GameItemNet.new(Vector2i(17,1), 4, Types.Item.Net, 1, false, "Net", Vector2i.ZERO, false)
	item_list[Types.Item.String] = GameItem.new(Vector2i(16,1), 4, Types.Item.String, 1, false, "String", Vector2i(16,1), false)
	item_list[Types.Item.BoneEnemy] = GameItemBoneEnemy.new(Vector2i(14,0), 4, Types.Item.BoneEnemy, 1, false, "Bone Enemy", Vector2i.ZERO, false)
	# Pickaxe tiers: power is the gather time in seconds, bonus_yield_chance is the
	# odds of an extra drop. Each tier is faster AND more productive than the last,
	# and every tier is kept in this one block so that invariant is checkable by
	# eye — the gold tier's art happens to live on the placeholder sheet (source 10),
	# which is a rendering detail, not a reason to register it somewhere else.
	#
	# Gather time falls per tier (2.0 / 1.8 / 1.6 / 1.2 / 0.7 / 0.45) and the extra-drop
	# chance climbs. Stone is the shallowest step on purpose — it is craftable on day
	# one out of the most common drop in the game, so it has to read as "slightly
	# better, right now" rather than as a tier that competes with copper.
	# The gold tier's step is deliberately the smallest of the rest of the ladder:
	# it costs several times what the iron one does, so most of what the player is
	# buying at the top is the +0.75 yield, not the speed.
	#
	# Copper sits between wood and bone. It exists because copper arrives with the
	# furnace (Industry tier 1) and would otherwise be an ore with no tool of its own —
	# the one tier you smelt purely to feed a later recipe.
	item_list[Types.Item.WoodPickaxe] = GameItemPickaxe.new(Vector2i(12,0), 4, Types.Item.WoodPickaxe, 1, false, "Wooden Pickaxe", Vector2i.ZERO, false, 2.0, 0.0)
	item_list[Types.Item.StonePickaxe] = GameItemPickaxe.new(Vector2i(5, 3), 10, Types.Item.StonePickaxe, 1, false, "Stone Pickaxe", Vector2i.ZERO, false, 1.8, 0.05)
	item_list[Types.Item.CopperPickaxe] = GameItemPickaxe.new(Vector2i(4, 3), 10, Types.Item.CopperPickaxe, 1, false, "Copper Pickaxe", Vector2i.ZERO, false, 1.6, 0.15)
	item_list[Types.Item.BonePickaxe] = GameItemPickaxe.new(Vector2i(12,1), 4, Types.Item.BonePickaxe, 1, false, "Bone Pickaxe", Vector2i.ZERO, false, 1.2, 0.25)
	item_list[Types.Item.IronPickaxe] = GameItemPickaxe.new(Vector2i(6,1), 4, Types.Item.IronPickaxe, 1, false, "Iron Pickaxe", Vector2i.ZERO, false, 0.7, 0.5)
	item_list[Types.Item.GoldPickaxe] = GameItemPickaxe.new(Vector2i(5, 4), 10, Types.Item.GoldPickaxe, 1, false, "Gold Pickaxe", Vector2i.ZERO, false, 0.45, 0.75)
	item_list[Types.Item.Food] = GameItemConsumable.new(Vector2i(15, 0), 4, Types.Item.Food, 1, false, "Food", Vector2i.ZERO, false, 4)
	item_list[Types.Item.Sword] = GameItemSword.new(Vector2i(6, 0), 4, Types.Item.Sword, 1, false, "Sword", Vector2i.ZERO, false, 4)
	item_list[Types.Item.X] = GameItem.new(Vector2i(16, 0), 4, Types.Item.X, 1, false, "X", Vector2i.ZERO, false)

	# --- Ore tiers and currency drawn from the generated placeholder sheet
	# (tileset source 10). Swapping any of these onto real art is a two-value edit:
	# change the atlas coordinate and the source id back to 4.
	item_list[Types.Item.Coin] = GameItem.new(Vector2i(4, 4), 10, Types.Item.Coin, 1, false, "Gold Coin", Vector2i.ZERO, false)
	item_list[Types.Item.CopperOre] = GameItem.new(Vector2i(0, 4), 10, Types.Item.CopperOre, 1, false, "Copper Ore", Vector2i.ZERO, false)
	item_list[Types.Item.GoldOre] = GameItem.new(Vector2i(1, 4), 10, Types.Item.GoldOre, 1, false, "Gold Ore", Vector2i.ZERO, false)
	item_list[Types.Item.CopperBar] = GameItem.new(Vector2i(2, 4), 10, Types.Item.CopperBar, 1, false, "Copper Bar", Vector2i.ZERO, false)
	item_list[Types.Item.GoldBar] = GameItem.new(Vector2i(3, 4), 10, Types.Item.GoldBar, 1, false, "Gold Bar", Vector2i.ZERO, false)
	# The gold pickaxe is registered with the rest of the pickaxe ladder above.

	# --- The stone building set, on its own generated sheet (tileset source 11,
	# tools/generate_stone_build_art.gd). Both are recolours of the wood pair above and
	# behave identically: the floor is an ordinary layer-2 placeable, and the wall
	# autotiles off the atlas coordinate below, which is the top-left cell of its blob
	# exactly as (0, 11) is for the wood wall. main.gd's WALL_TYPES is what ties that
	# coordinate to terrain 2 - registering a wall here alone would place a single
	# unconnected tile.
	item_list[Types.Item.StoneFloor] = GameItemFloor.new(Vector2i(0, 6), GameItem.STONE_BUILD_SOURCE_ID, Types.Item.StoneFloor, 2, true, "Stone Floor", Vector2i.ZERO)
	item_list[Types.Item.StoneWall] = GameItemWall2.new(Vector2i(0, 4), GameItem.STONE_BUILD_SOURCE_ID, Types.Item.StoneWall, 1, true, "Stone Wall", Vector2i.ZERO)

	
	
	
func get_item_by_data(atlas_location, source_id):
	for key in item_list.keys():
		if item_list[key].atlas_location == atlas_location and item_list[key].tile_source_id == source_id :
			return item_list[key]
			
func get_item(type: Types.Item) -> GameItem:
	return item_list[type]

func get_type(_name):
	for key in item_list.keys():
		if item_list[key].name == _name:
			return item_list[key].type
			
func get_all_types():
	var types = []
	for key in item_list:
		types.append(key)
	return types
	
