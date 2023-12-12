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
	#selected_item_manager.placed_tile.connect(Callable(self, "_on_placed_tile"))
	
	
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

func _on_placed_tile(type: Types.Item):
	inventory_manager.RemoveItem(type)
	if not inventory_manager.HasItem(type):
		selected_item_manager.ClearSelection()

func remove_item(_item):
	update_ui()

func update_ui():
	for i in range(21):
		item_grid.get_child(i).get_child(1).get_child(0).texture = null
		item_grid.get_child(i).get_child(2).text = ""
		var slotButton = item_grid.get_child(i)
		if slotButton is SlotButton:
			slotButton.clear_slot()

	var i = 0
	var inv = inventory_manager.get_inventory()
	for inv_slot in inv:
		if inv_slot.item == null:
			continue
		var item = inv_slot.item
		var atlas = item.get_atlas()

		item_grid.get_child(i).get_child(1).get_child(0).texture = atlas
		item_grid.get_child(i).get_child(2).text = str(inv_slot.count)
		
		var slotButton = item_grid.get_child(i)
		if slotButton is SlotButton:
			slotButton.set_slot(inv_slot)
			
		i += 1
			
func _on_Button_pressed(inventory_slot: InventorySlot, _instance: SlotButton):
	print("ui press")
	if selected_item_manager.selected_inventory_slot_item != null:
		if selected_item_manager.type == selected_item_manager.Type.Chest:
			inventory_manager.AddItem(selected_item_manager.selected_inventory_slot_item.item, 
			selected_item_manager.selected_inventory_slot_item.count)
			
			chest_inventory.remove_all_of_item(selected_item_manager.selected_inventory_slot_item.item.type)
			selected_item_manager.ClearSelection()

			
			update_ui()
	elif inventory_slot and inventory_slot.item != null: 
		selected_item_manager.SetSelectedItem(inventory_slot, selected_item_manager.Type.Inventory)
	
