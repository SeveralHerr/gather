extends Node
class_name Resources


var resources: Dictionary = {}

# Called when the node enters the scene tree for the first time.
func _ready():
	gameItems[GameItem.Type.Stone] = GameItem.new(Vector2i(1, 2), 4, GameItem.Type.Stone)
	gameItems[GameItem.Type.Wood] = GameItem.new(Vector2i(2, 2), 4, GameItem.Type.Wood)
	gameItems[GameItem.Type.Plank] = GameItem.new(Vector2i(3, 2), 4, GameItem.Type.Plank)
	gameItems[GameItem.Type.Sawmill] = GameItem.new(Vector2i(0, 0), 2, GameItem.Type.Sawmill)
	
	resources[Resource.]

func GetItemByName(name):
	for item in items:
		if item.name == name: 
			return item
			
func Get(type: GameItem.Type) -> GameItem:
	return gameItems[type]
