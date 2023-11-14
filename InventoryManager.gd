extends Node
class_name InventoryManager

@export var inventory = {}
@export var ui: UI

# Called when the node enters the scene tree for the first time.
func _ready():
	pass # Replace with function body.

		
func AddItem(item: GameItem, count: int = 0):
	var inventoryItem = InventorySlot.new(item, count)
	var found = false
	if inventory.has(item.type):
		inventory[item.type].count += inventoryItem.count
		found = true
	if found == false:
		inventory[item.type] = inventoryItem
	
	ui.add_item()
	
func HasItem(type: GameItem.Type) -> bool:
	return inventory.has(type)
	
func HasItems(type: GameItem.Type, count: int) -> bool:
	var qty = get_quantity(type)
	
	return qty == count
	
func get_quantity(type: GameItem.Type):
	if not inventory.has(type):
		return "0"
	
	return inventory[type].count
	
	
func RemoveItem(type: GameItem.Type):
	if inventory.has(type):
		inventory[type].count -= 1
		
	if inventory[type].count <= 0:
		inventory.erase(type)
			
	ui.update_ui()
