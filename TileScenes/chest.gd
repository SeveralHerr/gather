extends StaticBody2D
class_name ChestInventory

var chest_inventory = {}

var player: Player = null
@onready var player_range = $PlayerRange

# Called when the node enters the scene tree for the first time.
func _ready():
	add_to_group("Chests")
	add_to_group("SaveLoad")
	add_to_group("SaveChunks")
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
					inputNode.isUiOpen = true
					
			if player_range.target != null:
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

	var dict := {
		"filepath": get_path(),
		"inventory": inventory_data
	}
	return dict
	
func save():
	var inventory_data = []
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

	return dict
	
func load(dict):
	var json = JSON.new()
	for i in dict["data"]:
		json.parse(i)
		var data = json.get_data()

		var count = data["count"]
		var type = data["itemType"]
		
		var items = get_tree().get_nodes_in_group("Items")
		for it in items: 
			if it is Items:
				chest_inventory[type] = InventorySlot.new(it.get_item(type), count)
	
	
func loadObject(loadedDict: Dictionary) -> void:
	chest_inventory = {}
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

				chest_inventory[int(node["itemType"])] = InventorySlot.new(itemm, node["count"])
	
		
		
