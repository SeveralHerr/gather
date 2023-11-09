extends Node
class_name InventoryManager

var inventory = []
@export var ui: UI

# Called when the node enters the scene tree for the first time.
func _ready():
	pass # Replace with function body.


# Called every frame. 'delta' is the elapsed time since the previous frame.
func f_process(delta):
	for key in inventory.keys():
		print(inventory[key])
		
func AddItem(item: Item, count: int = 0):
	var inventoryItem = InventorySlot.new(item, count)
	var found = false
	for i in range(inventory.size()):
		if inventory[i].item == inventoryItem.item:
			inventory[i].count += inventoryItem.count
			found = true
	if found == false:
		inventory.append(inventoryItem)
	
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
