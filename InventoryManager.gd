extends Node
class_name InventoryManager

var inventory = {}
@export var ui: UI

# Called when the node enters the scene tree for the first time.
func _ready():
	pass # Replace with function body.


# Called every frame. 'delta' is the elapsed time since the previous frame.
func f_process(delta):
	for key in inventory.keys():
		print(inventory[key])
		
func AddItem(item: Item, count: int = 0):
	if not inventory.has(item):
		inventory[item] = 0

	inventory[item] += count
	
	ui.add_item()


func fAddItem(item: Item, count: int = 1):
	var found = false
	for key in inventory.keys(): 
		if key.name == item.name:
			inventory[key] += 1
			found = true

	if found == false:
		inventory[item] = count
		ui.add_item()
