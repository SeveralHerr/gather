extends Control
class_name UI
var inventory
@export var tileMapHandler: TileMapHandler
@export var selected_item_manager: SelectedItemManager
@export var inventory_manager: InventoryManager
@export var Slot = preload("res://Slot.tscn")
@export var item_grid: GridContainer
@export var test: Node
@export var furnaceUi: Node
@onready var chest_inventory = $ChestInventory

func _ready():
	#test = $SawmillUI
	#furnaceUi = $FurnaceUi
	add_to_group("UI")
	for child in item_grid.get_children():
		child.queue_free()
		
	for item in range(21):
		var slot = Slot.instantiate()
		item_grid.add_child(slot)
		
		var slotButton = item_grid.get_child(item)
		if slotButton is SlotButton:
			#slotButton.item = chest_inventory.chest_inventory[key].item
			slotButton.slot_clicked.connect(_on_Button_pressed)
		
func add_item():
	update_ui()


func remove_item(item):
	update_ui()

func update_ui():
	for i in range(21):
		item_grid.get_child(i).get_child(1).get_child(0).texture = null
		item_grid.get_child(i).get_child(2).text = ""

	var i = 0
	for key in inventory_manager.inventory.keys():
		var atlas = inventory_manager.inventory[key].item.get_atlas()

		item_grid.get_child(i).get_child(1).get_child(0).texture = atlas
		item_grid.get_child(i).get_child(2).text = str(inventory_manager.inventory[key].count)
		
		var slotButton = item_grid.get_child(i)
		if slotButton is SlotButton:
			slotButton.inventory_slot_item = inventory_manager.inventory[key]
			
		i += 1
			
func _on_Button_pressed(inventory_slot: InventorySlot):
	if selected_item_manager.selected_inventory_slot_item != null:
		inventory_manager.AddItem(selected_item_manager.selected_inventory_slot_item.item, selected_item_manager.selected_inventory_slot_item.count)
		chest_inventory.remove_all_of_item(selected_item_manager.selected_inventory_slot_item.item.type)
		selected_item_manager.ClearSelection()
		
		update_ui()
	else: 
		selected_item_manager.SetSelectedItem(inventory_slot)
	
