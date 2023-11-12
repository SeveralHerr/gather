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

	gameItems

func GetItemByName(name):
	for item in items:
		if item.name == name: 
			return item
