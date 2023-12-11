extends StaticBody2D
class_name TestChest

signal toggle_inventory(external_inventory_owner)

@onready var new_inv_manager = get_tree().get_nodes_in_group("InventoryManager")[1]  
@export var inventory_data: InventoryData

func player_interact() -> void:
	toggle_inventory.emit(self)

func _ready():
	add_to_group("external_inventory")
	add_to_group("SaveChunks")
	inventory_data = InventoryData.new()
	inventory_data.inventory_slot_datas.append(SlotData.new(GameItems.get_item(Types.Item.IronBar), 1) as SlotData)
	inventory_data.inventory_slot_datas.append(SlotData.new(GameItems.get_item(Types.Item.IronBar), 9) as SlotData)
	inventory_data.inventory_slot_datas.append(null)
	toggle_inventory.connect(new_inv_manager._toggle_inventory)
	pass # Replace with function body.

func save():
	var inv = []
	for i in inventory_data.inventory_slot_datas.size():
		var item = inventory_data.inventory_slot_datas[i]
		
		var json 
		if not item:
			json = {
				"type": 1337,
				"count": 1337
			}
		else:
			json = {
				"type": item.item.type,
				"count": item.count
			}

		inv.append(JSON.stringify(json))
	
	var dict = {
		"x": position.x,
		"y": position.y,
		"data": inv,
		"filepath": "343"
	}

	return dict
	
func load(dict):
	inventory_data.inventory_slot_datas = []
	for i in dict.data.size():
		var saved_info = dict.data[i]
		var json = JSON.new()
		json.parse(saved_info)
		var node = json.get_data()
		
		if node["type"] == 1337 and node["count"] == 1337:
			inventory_data.inventory_slot_datas.append(null)
		else:
			inventory_data.inventory_slot_datas.append(SlotData.new(GameItems.get_item(node["type"]), node["count"]))
	inventory_data.inv_updated()
