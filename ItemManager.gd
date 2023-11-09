extends Node
class_name ItemManager

var itemsInWorld = {}
@export var player: Player
@export var items: Items
@export var inventoryManager: InventoryManager

# Called when the node enters the scene tree for the first time.
func _ready():
	pass # Replace with function body.


# Called every frame. 'delta' is the elapsed time since the previous frame.
func _process(delta):
	var activation_distance = 30.0
	var move_speed = 20.0
	
	if itemsInWorld.size() > 0:
	
		for key in itemsInWorld.keys():
			var direction = player.global_position - itemsInWorld[key].global_position
			var distance = direction.length()

			if distance < activation_distance and distance >= 0:
				direction = direction.normalized()
				itemsInWorld[key].global_position += direction * move_speed * delta
				
			if int(itemsInWorld[key].global_position.x) == int(player.global_position.x) and  int(itemsInWorld[key].global_position.y) == int(player.global_position.y) :
				inventoryManager.AddItem(key, 1)
				itemsInWorld[key].queue_free()

				itemsInWorld.erase(key)


func AddItemToWorld(position, item):
	var instance = items.GetItemByName(item).scene.instantiate()
	add_child(instance)
	add_to_group("Items")
	instance.position = position
	itemsInWorld[item] = instance
	
