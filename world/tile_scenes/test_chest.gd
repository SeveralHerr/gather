extends StaticBody2D
class_name TestChest

signal toggle_inventory(external_inventory_owner)

## Type-checked rather than indexed. This was `[1]`, which only worked because
## main.tscn's root node was itself declared in the "InventoryManager" group and
## sorted ahead of the real manager. Those stale root groups are gone, so `[1]` is
## now out of bounds — and an index was never the right lookup regardless.
@onready var new_inv_manager: NewInventoryManager = _find_inventory_manager()


func _find_inventory_manager() -> NewInventoryManager:
	for node in get_tree().get_nodes_in_group("InventoryManager"):
		if node is NewInventoryManager:
			return node
	push_error("TestChest: no NewInventoryManager in the InventoryManager group")
	return null

@export var inventory_data: InventoryData

func player_interact() -> void:
	toggle_inventory.emit(self)

func _ready():
	add_to_group("external_inventory")
	add_to_group("SaveChunks")
	inventory_data = InventoryData.new()
	inventory_data.inventory_slot_datas.append(null)
	inventory_data.inventory_slot_datas.append(null)
	inventory_data.inventory_slot_datas.append(null)
	toggle_inventory.connect(new_inv_manager._toggle_inventory)
	pass # Replace with function body.

func save():
	var inv = []
	for i in inventory_data.inventory_slot_datas.size():
		var item = inventory_data.inventory_slot_datas[i]
		
		var json
		# `if not item:` is FALSE for a live SlotData whose .item is null, so the else
		# branch dereferenced it and raised. `func save()` is untyped, so the raise
		# returned null: a blank line in saveFile and the whole chest's contents gone,
		# with no error the player could see. Same shape as the bug fixed in player.gd.
		if item == null or item.item == null:
			json = {
				"type": 1337,
				"count": 1337
			}
		else:
			json = {
				"type": item.item.type,
				"count": item.count
			}

		inv.append(json)
	
	var dict = {
		"x": position.x,
		"y": position.y,
		"data": inv,
		"filepath": "343"
	}

	return dict
	
## Every value here comes from JSON.parse of a file on disk, so nothing about its shape is
## guaranteed. `func load(dict)` is untyped, so an unguarded index that raises returns null
## and aborts — with inventory_slot_datas already reset to [] on the first line, which is
## what turns "one bad slot" into "this chest is now empty" (gather-wfu).
func load(dict):
	if typeof(dict) != TYPE_DICTIONARY:
		return

	var saved: Variant = dict.get("data", [])
	if saved is not Array:
		return

	inventory_data.inventory_slot_datas = []
	# decode_entries reads both the pre-gather-usv JSON strings and the nested dictionaries
	# written now. A slot it drops must still take a place in the list, or every slot after
	# it shifts down one and the chest silently rearranges itself.
	for node in SaveLoad.decode_entries(saved):
		if not (node.has("type") and node.has("count")):
			push_warning("TestChest: skipping a malformed slot")
			inventory_data.inventory_slot_datas.append(null)
			continue

		var type := int(node["type"])
		var count := int(node["count"])
		if type == 1337 and count == 1337:
			inventory_data.inventory_slot_datas.append(null)
			continue

		# get_item() answers null for a type it does not hold rather than raising
		# (gather-5rj). An empty slot is the right cost for one unknown item; aborting
		# here would drop every slot after it.
		var item: GameItem = GameItems.get_item(type)
		if item == null:
			push_warning("TestChest: no item registered for type %d, that slot is empty" % type)
			inventory_data.inventory_slot_datas.append(null)
			continue

		inventory_data.inventory_slot_datas.append(SlotData.new(item, count))
	inventory_data.inv_updated()
