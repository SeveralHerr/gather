extends Node

const PICK_UP = preload("res://Items/PickUp.tscn")
const SHADOW = preload("res://shadow.tscn")

func _ready():
	add_to_group("SaveLoad")
	randomize()


func create(slot_data: SlotData, position: Vector2):
	var pick_up = PICK_UP.instantiate()
	var shadow = SHADOW.instantiate()
	

	var initial_velocity = Vector2(randf_range(-15, 15), randf_range(-70, -60))
	pick_up.linear_velocity = initial_velocity
	get_node("/root/Main/Node2D/PickUps").add_child(pick_up)
	get_node("/root/Main/Node2D/PickUps").add_child(shadow)
	pick_up.slot_data = slot_data
	shadow.target = pick_up
	pick_up.shadow = shadow
	
	var random_x = randf_range(-3, 3)
	var random_y = randf_range(-3, 3)
	pick_up.position = position + Vector2(random_x, random_y)
	shadow.position = pick_up.position
	pick_up.y_sort_enabled = true
	if slot_data.item.is_scene_tile:
		pick_up.sprite_2d.scale= Vector2(0.5, 0.5) 
	pick_up.sprite_2d.texture = slot_data.item.get_atlas()

	#get_tree().root.add_child(pickup)


func create_pickup(item: GameItem, position: Vector2):
	var slot_data: SlotData = SlotData.new()
	slot_data.item = item
	slot_data.count = 1
	PickUpManager.create(slot_data, position)


func saveObject() -> Dictionary:
	var world_item_data = {}
	var pickups_in_world = get_node("/root/Main/Node2D/PickUps").get_children()
	
	for i in pickups_in_world.size():
		var json = {
			"itemType": pickups_in_world[i].slot_data.item.type,
			"x": pickups_in_world[i].position.x,
			"y": pickups_in_world[i].position.y
		}
		
		world_item_data[i] = JSON.stringify(json)
	
	var dict := {
		"filepath": get_path(),
		"world_items": world_item_data
	}
	return dict
	
func loadObject(loadedDict: Dictionary) -> void:

	
	for child in get_node("/root/Main/Node2D/PickUps").get_children(): 
		child.queue_free()
	
	for item in loadedDict.world_items.keys():
		var x = loadedDict.world_items[item]
		var json = JSON.new()
		json.parse(x)
		var node = json.get_data()
		var pos = Vector2i(node["x"], node["y"])
		var newItem = GameItems.get_item(node["itemType"])
		
		create_pickup( newItem, pos)
