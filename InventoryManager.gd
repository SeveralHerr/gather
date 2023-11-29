extends Node
class_name InventoryManager



@onready var selected_item_manager: SelectedItemManager = $"../Node2D/Player/Camera2D/UI/SelectedItemManager"


@export var inventory = {}
@export var items: Items
@export var ui: UI

# Called when the node enters the scene tree for the first time.
func _ready():
	add_to_group("SaveLoad")
	AddItem(GameItems.get_item(Types.Item.Wood), 100)
	AddItem(items.get_item(Types.Item.Stone), 100)
	AddItem(items.get_item( Types.Item.Sawmill), 1)
	AddItem(items.get_item( Types.Item.WoodPickaxe), 1)
	AddItem(items.get_item( Types.Item.IronPickaxe), 1)
	AddItem(items.get_item( Types.Item.BoneTurret), 1)
	AddItem(items.get_item( Types.Item.BoneEnemy), 1)
	selected_item_manager.placed_tile.connect(_on_placed_tile)
	pass # Replace with function body.

func get_inventory() -> Array:
	return inventory.values()
func AddItem(item: GameItem, count: int = 0):
	var inventoryItem = InventorySlot.new(item, count)
	var found = false
	if inventory.has(item.type):
		inventory[item.type].count += inventoryItem.count
		found = true
	if found == false:
		inventory[item.type] = inventoryItem
	
	ui.add_item()
	
func HasItem(type: Types.Item) -> bool:
	return inventory.has(type)
	
func HasItems(type: Types.Item, count: int) -> bool:
	var qty = get_quantity(type)

	return qty >= count
	
func get_quantity(type: Types.Item):
	if not inventory.has(type):
		return 0
	
	return inventory[type].count
	
func remove_all_of_item(type: Types.Item):
	if not inventory.has(type):
		return
		
	inventory.erase(type)
			
	ui.update_ui()
	
	
func RemoveItem(type: Types.Item):
	if inventory.has(type):
		inventory[type].count -= 1
		
	if inventory[type].count <= 0:
		inventory.erase(type)
			
	ui.update_ui()


func _on_placed_tile(item: GameItem):
	RemoveItem(item.type)
	if not HasItem(item.type):
		selected_item_manager.ClearSelection()
		print("clear")
		ui.update_ui()

func saveObject() -> Dictionary:
	var inventory_data = {}
	for item in inventory.keys():
		var json = {
			"itemType": item,
			"count": inventory.get(item).count
		}
		
		inventory_data[item] = JSON.stringify(json)
	
	var dict := {
		"filepath": get_path(),
		"inventory": inventory_data
	}
	return dict
	
func loadObject(loadedDict: Dictionary) -> void:
	inventory = {}
	for item in loadedDict.inventory.keys():
		var x = loadedDict.inventory.get(item)
		var json = JSON.new()
		json.parse(x)
		var node = json.get_data()
		AddItem(items.get_item( node["itemType"]), node["count"] )
		
	ui.update_ui()
