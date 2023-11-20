extends Control

@onready var sawmill_button: Button = $SawmillButton
@onready var furnace_button: Button = $FurnaceButton
@onready var selected_item_manager: SelectedItemManager = $"../SelectedItemManager"
@onready var items: Items = $"../../../../../Items"
@onready var inventory_manager: InventoryManager = $"../../../../../InventoryManager"



# Called when the node enters the scene tree for the first time.
func _ready():
	sawmill_button.connect("pressed", Callable(self, "_on_sawmill_button_pressed"))
	furnace_button.connect("pressed", Callable(self, "_on_furnace_button_pressed"))

# Called every frame. 'delta' is the elapsed time since the previous frame.
func _process(delta):
	pass

func _on_sawmill_button_pressed():
	inventory_manager.AddItem(items.get_item(Types.Item.Sawmill), 1)
	pass
	
func _on_furnace_button_pressed():
	pass
