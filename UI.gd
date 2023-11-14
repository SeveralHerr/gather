extends Control
class_name UI
var inventory
@export var tileMapHandler: TileMapHandler
@export var selectedItemManager: SelectedItemManager
@export var inventoryManager: InventoryManager
@export var Slot = preload("res://Slot.tscn")
@export var item_grid: GridContainer
@export var test: Node
@export var furnaceUi: Node

func _ready():
	test = $SawmillUI
	furnaceUi = $FurnaceUi
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
	for i in range(8):
		item_grid.get_child(i).get_child(0).get_child(0).texture = null
		item_grid.get_child(i).get_child(1).text = ""

	var i = 0
	for key in inventoryManager.inventory.keys():
		var button = item_grid.get_child(i).get_child(0).get_child(1)
		button.connect("pressed", Callable(button, "_on_Button_pressed"))

		var instance = TextureRect.new()
		var location = Rect2(inventoryManager.inventory[key].item.atlas_location.x*16, inventoryManager.inventory[key].item.atlas_location.y*16, 16, 16)
		
		var atlas_texture = AtlasTexture.new()
		atlas_texture.atlas = load("res://Resources/game_items_atlas.tres")
		atlas_texture.region = location
	
		item_grid.get_child(i).get_child(0).get_child(0).texture = atlas_texture
		item_grid.get_child(i).get_child(1).text = str(inventoryManager.inventory[key].count)
		
		var slotButton = item_grid.get_child(i)
		if slotButton is SlotButton:
			slotButton.item = inventoryManager.inventory[key].item
			slotButton.slot_clicked.connect(_on_Button_pressed)
			#selectedItemManager.SetSelectedItem(inventoryManager.inventory[key].item)
			
		i += 1
			
func _on_Button_pressed(item: GameItem):
	if item.isPlaceable == true:
		selectedItemManager.SetSelectedItem(item)
