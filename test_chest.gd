extends StaticBody2D
class_name TestChest

signal toggle_inventory(external_inventory_owner)

@onready var new_inv_manager = get_tree().get_nodes_in_group("InventoryManager")[1]  
@export var inventory_data: InventoryData

func player_interact() -> void:
	toggle_inventory.emit(self)

func _ready():
	add_to_group("external_inventory")
	inventory_data = InventoryData.new()
	inventory_data.inventory_slot_datas.append(SlotData.new(GameItems.get_item(Types.Item.IronBar), 1) as SlotData)
	inventory_data.inventory_slot_datas.append(SlotData.new(GameItems.get_item(Types.Item.IronBar), 9) as SlotData)
	inventory_data.inventory_slot_datas.append(null)
	toggle_inventory.connect(new_inv_manager._toggle_inventory)
	pass # Replace with function body.

