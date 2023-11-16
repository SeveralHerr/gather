extends Node
class_name Items

var item_list: Dictionary = {}

# Called when the node enters the scene tree for the first time.
func _ready():
	item_list[Types.Item.Stone] = GameItem.new(Vector2i(1, 2), 4, Types.Item.Stone, 1, false, "Stone", Vector2i.ZERO)
	item_list[Types.Item.Wood] = GameItem.new(Vector2i(2, 2), 4, Types.Item.Wood, 1, false, "Wood", Vector2i.ZERO)
	item_list[Types.Item.Plank] = GameItem.new(Vector2i(3, 2), 4, Types.Item.Plank, 1, false, "Plank", Vector2i.ZERO)
	item_list[Types.Item.Sawmill] = GameItem.new(Vector2i(0, 0), 2, Types.Item.Sawmill, 1, true, "Sawmill", Vector2i.ZERO, true)
	item_list[Types.Item.WoodFloor] = GameItem.new(Vector2i(4, 2), 4, Types.Item.WoodFloor, 2, true, "Wood Floor", Vector2i.ZERO)
	item_list[Types.Item.CoalOre] = GameItem.new(Vector2i(5, 2), 4, Types.Item.CoalOre, 1, false, "Coal Ore", Vector2i.ZERO)
	item_list[Types.Item.IronOre] = GameItem.new(Vector2i(6, 2), 4, Types.Item.IronOre, 1, false, "Iron Ore", Vector2i.ZERO)
	item_list[Types.Item.IronBar] = GameItem.new(Vector2i(7, 2), 4, Types.Item.IronBar, 1, false, "Iron Bar", Vector2i.ZERO)
	item_list[Types.Item.WoodWall] = GameItem.new(Vector2i(0, 11), 4, Types.Item.WoodWall, 1, true, "Wood Wall", Vector2i.ZERO)
	item_list[Types.Item.Furnace] = GameItem.new(Vector2i(0, 0), 5, Types.Item.Furnace, 1, true, "Furnace", Vector2i.ZERO, true)
	item_list[Types.Item.WoodDoor] = GameItem.new(Vector2i(0,0), 1, Types.Item.WoodDoor, 1, true, "Wood Door", Vector2i(0, 13), true)
	item_list[Types.Item.Grass] = GameItem.new(Vector2i(0,0), 4, Types.Item.Grass, 0, false, "Grass", Vector2i.ZERO)


func get_item_by_data(atlas_location, source_id):
	for key in item_list.keys():
		if item_list[key].atlas_location == atlas_location and item_list[key].tile_source_id == source_id :
			return item_list[key]
			
func get_item(type: Types.Item) -> GameItem:
	return item_list[type]

func get_type(name):
	for key in item_list.keys():
		if item_list[key].name == name:
			return item_list[key].type
	
