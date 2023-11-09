extends Control
class_name UI
var inventory
@export var inventoryManager: InventoryManager
@export var Slot = preload("res://Slot.tscn")
@export var item_grid: GridContainer

	

func _ready():
	for child in item_grid.get_children():
		child.queue_free()
		
	for item in range(8):
		var slot = Slot.instantiate()
		item_grid.add_child(slot)

func add_item():
	update_ui()

func remove_item(item):
	update_ui()

func update_ui():
	for i in inventoryManager.inventory.size():
		item_grid.get_child(i).get_child(0).get_child(0).texture = inventoryManager.inventory[i].item.icon
		item_grid.get_child(i).get_child(1).text = str(inventoryManager.inventory[i].count)

		

func fupdate_ui():
	# Clear the existing UI
	for child in $Panel/GridContainer.get_children():
		child.queue_free()
	
	print(inventoryManager.inventory)
	for item in inventoryManager.inventory.keys():
		var button = Button.new()
		$Panel/GridContainer.add_child(button)
				
		var item_icon = TextureRect.new()
		item_icon.texture = item.icon # Assuming each item has an 'icon' property
		$Panel/GridContainer.get_child(0).add_child(item_icon)
		




		button.connect("pressed", Callable(self, "_on_Button_pressed"))
		
		var label = Label.new()
		label.text = str(inventoryManager.inventory[item])
		label.scale *= 0.3
		$Panel/GridContainer.add_child(label)
		
func _on_Button_pressed():
	print("Button was pressed!")
