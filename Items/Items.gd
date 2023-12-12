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
	item_list[Types.Item.Net] = GameItemNet.new(Vector2i(17,1), 4, Types.Item.Net, 1, false, "Net", Vector2i.ZERO, false)
	item_list[Types.Item.String] = GameItem.new(Vector2i(16,1), 4, Types.Item.String, 1, false, "String", Vector2i(16,1), false)
	item_list[Types.Item.BoneEnemy] = GameItemBoneEnemy.new(Vector2i(14,0), 4, Types.Item.BoneEnemy, 1, false, "Bone Enemy", Vector2i.ZERO, false)
	item_list[Types.Item.WoodPickaxe] = GameItemPickaxe.new(Vector2i(12,0), 4, Types.Item.WoodPickaxe, 1, false, "Wooden Pickaxe", Vector2i.ZERO, false, 2)
	item_list[Types.Item.IronPickaxe] = GameItemPickaxe.new(Vector2i(6,1), 4, Types.Item.IronPickaxe, 1, false, "Iron Pickaxe", Vector2i.ZERO, false, 1)
	item_list[Types.Item.BonePickaxe] = GameItemPickaxe.new(Vector2i(12,1), 4, Types.Item.BonePickaxe, 1, false, "Bone Pickaxe", Vector2i.ZERO, false, 1)
	item_list[Types.Item.Food] = GameItemConsumable.new(Vector2i(15, 0), 4, Types.Item.Food, 1, false, "Food", Vector2i.ZERO)
	item_list[Types.Item.Sword] = GameItemSword.new(Vector2i(6, 0), 4, Types.Item.Sword, 1, false, "Sword", Vector2i.ZERO, false, 4)
	
	
	
	
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
	
