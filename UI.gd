extends Control
class_name UI
var inventory
@export var inventoryManager: InventoryManager
	

func _ready():
	update_ui()

func add_item():
	update_ui()

func remove_item(item):
	update_ui()

func update_ui():
	# Clear the existing UI
	for child in $Panel/GridContainer.get_children():
		child.queue_free()
	
	print(inventoryManager.inventory)
	for item in inventoryManager.inventory.keys():
		var item_icon = TextureRect.new()
		item_icon.texture = item.icon # Assuming each item has an 'icon' property
		$Panel/GridContainer.add_child(item_icon)
		
		var label = Label.new()
		label.text = str(inventoryManager.inventory[item])
		$Panel/GridContainer.add_child(label)
