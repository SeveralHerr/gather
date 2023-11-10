extends Control
class_name UI
var inventory
@export var tileMapHandler: TileMapHandler
@export var selectedItemManager: SelectedItemManager
@export var inventoryManager: InventoryManager
@export var Slot = preload("res://Slot.tscn")
@export var item_grid: GridContainer


func _ready():
	add_to_group("UI")
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
		var button = item_grid.get_child(i).get_child(0).get_child(1)
		button.connect("pressed", Callable(button, "_on_Button_pressed"))

		item_grid.get_child(i).get_child(0).get_child(0).texture = inventoryManager.inventory[i].item.icon
		item_grid.get_child(i).get_child(1).text = str(inventoryManager.inventory[i].count)
		
		var slotButton = item_grid.get_child(i)
		if slotButton is SlotButton:
			slotButton.item = inventoryManager.inventory[i].item
			slotButton.slot_clicked.connect(_on_Button_pressed)
			
func _on_Button_pressed(item: Item):
	selectedItemManager.SetSelectedItem(item)
