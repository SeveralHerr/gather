extends Control
class_name ChestUi

var Slot = preload("res://Slot.tscn")

@export var chest_inventory: ChestInventory
@export var selected_item_manager: SelectedItemManager
@onready var grid_container = $PanelContainer/GridContainer
@onready var exit_button = $ExitButton
@onready var input_manager: InputManager = $"../../../../../InputManager"
@onready var inventory_manager: InventoryManager = $"../../../../../InventoryManager"



# Called when the node enters the scene tree for the first time.
func _ready():
	add_to_group("ChestUi")
	exit_button.connect("pressed", Callable(self, "_exit"))
	
	for child in grid_container.get_children():
		child.queue_free()
		
	for item in range(21):
		var slot = Slot.instantiate()
		grid_container.add_child(slot)

		#button.connect("pressed", Callable(button, "_on_Button_pressed"))
		var slotButton = grid_container.get_child(item)
		if slotButton is SlotButton:
			#slotButton.item = chest_inventory.chest_inventory[key].item
			slotButton.slot_clicked.connect(_on_Button_pressed)

func _exit():
	input_manager.isUiOpen = false
	visible = false


func update_ui():
	for i in range(21):
		grid_container.get_child(i).get_child(1).get_child(0).texture = null
		grid_container.get_child(i).get_child(2).text = ""

	var i = 0
	for key in chest_inventory.chest_inventory.keys():
		var atlas = chest_inventory.chest_inventory[key].item.get_atlas()
	
		grid_container.get_child(i).get_child(1).get_child(0).texture = atlas
		grid_container.get_child(i).get_child(2).text = str(chest_inventory.chest_inventory[key].count)
		
		var slotButton = grid_container.get_child(i)
		if slotButton is SlotButton:
			slotButton.inventory_slot_item = chest_inventory.chest_inventory[key]

		i += 1
		
func set_chest(chest: ChestInventory):
	chest_inventory = chest
	update_ui()
	
func remove_all_of_item(type: Types.Item):
	if not chest_inventory.chest_inventory.has(type):
		return
		
	chest_inventory.chest_inventory.erase(type)
			
	update_ui()

func _on_Button_pressed(inventory_slot: InventorySlot):
	if selected_item_manager.selected_inventory_slot_item != null:
		if selected_item_manager.type == selected_item_manager.Type.Inventory:
			inventory_manager.remove_all_of_item(selected_item_manager.selected_inventory_slot_item.item.type)
			chest_inventory.chest_inventory[selected_item_manager.selected_inventory_slot_item.item.type] = selected_item_manager.selected_inventory_slot_item
			selected_item_manager.ClearSelection()
			
			update_ui()
	else: 
		selected_item_manager.SetSelectedItem(inventory_slot, selected_item_manager.Type.Chest)
	

