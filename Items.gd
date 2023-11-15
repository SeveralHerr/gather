extends Node
class_name Items

@export var items: Array[Item] = []
var gameItems: Dictionary = {}

# Called when the node enters the scene tree for the first time.
func _ready():
	items = []
	items.append(Item.new(Vector2i(1, 0), preload("res://Resources/Tree.tscn"), "Tree", preload("res://Resources/Wood.png")))
	items.append(Item.new(Vector2i(2, 1), preload("res://Resources/Stone.tscn"), "Stone", preload("res://Resources/Stone.png")))
	items.append(Item.new(Vector2i.ZERO, null, "Plank", preload("res://Resources/Plank.png")))

	gameItems[GameItem.Type.Stone] = GameItem.new(Vector2i(1, 2), 4, GameItem.Type.Stone, 1, false)
	gameItems[GameItem.Type.Wood] = GameItem.new(Vector2i(2, 2), 4, GameItem.Type.Wood, 1, false)
	gameItems[GameItem.Type.Plank] = GameItem.new(Vector2i(3, 2), 4, GameItem.Type.Plank, 1, false)
	gameItems[GameItem.Type.Sawmill] = GameItem.new(Vector2i(0, 0), 2, GameItem.Type.Sawmill, 1, true)
	gameItems[GameItem.Type.WoodFloor] = GameItem.new(Vector2i(4, 2), 4, GameItem.Type.WoodFloor, 2, true)
	gameItems[GameItem.Type.CoalOre] = GameItem.new(Vector2i(5, 2), 4, GameItem.Type.CoalOre, 1, false)
	gameItems[GameItem.Type.IronOre] = GameItem.new(Vector2i(6, 2), 4, GameItem.Type.IronOre, 1, false)
	gameItems[GameItem.Type.IronBar] = GameItem.new(Vector2i(7, 2), 4, GameItem.Type.IronBar, 1, false)
	gameItems[GameItem.Type.Furnace] = GameItem.new(Vector2i(0, 0), 5, GameItem.Type.Furnace, 1, true)


func get_item_by_data(atlas_location, source_id):
	for key in gameItems.keys():
		if gameItems[key].atlas_location == atlas_location and gameItems[key].tile_source_id == source_id :
			return gameItems[key]

func get_enum_name_from_value(value):
	if value == GameItem.Type.CoalOre:
		return "Coal Ore"
	if value == GameItem.Type.IronBar:
		return "Iron Bar"
	if value == GameItem.Type.IronOre:
		return "Iron Ore"
	if value == GameItem.Type.Plank:
		return "Plank"
	if value == GameItem.Type.WoodFloor:
		return "Wood Floor"
	if value == GameItem.Type.Wood:
		return "Wood"
	return ""

func get_enum_from_name_test(value):
	if value == "Coal Ore":
		return GameItem.Type.CoalOre
	if value == "Iron Bar":
		return  GameItem.Type.IronBar
	if value == "Iron Ore":
		return GameItem.Type.IronOre
	if value == "Plank":
		return GameItem.Type.Plank
	if value == "Wood Floor":
		return GameItem.Type.WoodFloor
	if value == "Wood":
		return GameItem.Type.Wood
	return ""

func GetItemByName(name):
	for item in items:
		if item.name == name: 
			return item
			
func Get(type: GameItem.Type) -> GameItem:
	return gameItems[type]
