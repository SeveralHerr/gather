extends Area2D
class_name ChestInventory

var chest_inventory = {}


# Called when the node enters the scene tree for the first time.
func _ready():
	add_to_group("Chests")
	add_to_group("SaveLoad")
	add_to_group("SaveChunks")
	print("added")
	$Button.connect("pressed", Callable(self, "_on_button_open_chest"))
	pass # Replace with function body.


# Called every frame. 'delta' is the elapsed time since the previous frame.
func _process(delta):
	
	pass
	

func _on_button_open_chest():	
	var nodes = get_tree().get_nodes_in_group("ChestUi")
	for node in nodes:
		if node is ChestUi:
			var inputNodes = get_tree().get_nodes_in_group("InputManager")
			for inputNode in inputNodes:
				if inputNode is InputManager:
					print("open")
					inputNode.isUiOpen = true
			
			node.visible = true
			node.set_chest(self)
			
func saveObject() -> Dictionary:
	
	var inventory_data = {}
	for item in chest_inventory.keys():
		var json = {
			"itemType": item,
			"count": chest_inventory.get(item).count
		}

		inventory_data[item] = JSON.stringify(json)
	print("saving")
	var dict := {
		"filepath": get_path(),
		"inventory": inventory_data
	}
	return dict
	
func save():
	var inventory_data = {}
	for item in chest_inventory.keys():
		var json = {
			"itemType": item,
			"count": chest_inventory.get(item).count
		}
		inventory_data.append(JSON.stringify(json))
	
	var dict = {
		"x": position.x,
		"y": position.y,
		"data": inventory_data,
		"filepath": "343"
	}
	print("dict ",dict)
	return dict
	
func load(dict):
	print(dict)
	
func loadObject(loadedDict: Dictionary) -> void:
	chest_inventory = {}
	print("load")
	for item in loadedDict.inventory.keys():
		var x = loadedDict.inventory.get(item)
		var json = JSON.new()
		json.parse(x)
		var node = json.get_data()
		var nodes = get_tree().get_nodes_in_group("Items")
		var itemm
		for n in nodes:
			if n is Items:
				itemm = n.get_item(node["itemType"])

				chest_inventory[node["itemType"]] = InventorySlot.new(itemm, node["count"])
	
		
		
