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
	gameItems[GameItem.Type.Furnace] = GameItem.new(Vector2i(0, 0), 1, GameItem.Type.Furnace, 1, true)






func GetItemByName(name):
	for item in items:
		if item.name == name: 
			return item
			
func Get(type: GameItem.Type) -> GameItem:
	return gameItems[type]
