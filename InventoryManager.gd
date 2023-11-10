extends Node
class_name InventoryManager

var inventory = []
@export var ui: UI

# Called when the node enters the scene tree for the first time.
func _ready():
	pass # Replace with function body.

		
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
