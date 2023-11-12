extends Node
class_name ItemManager

@export var itemsInWorld: Array[WorldItem] = []
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
	
		for i in itemsInWorld.size():
			var playerPos = player.global_position - Vector2(8,8)
			var direction = playerPos - itemsInWorld[i].instance.global_position
			var distance = direction.length()

			if distance < activation_distance and distance >= 0:
				direction = direction.normalized()
				itemsInWorld[i].instance.global_position += direction * move_speed * delta
				
			if int(itemsInWorld[i].instance.global_position.x) == int(playerPos.x) and  int(itemsInWorld[i].instance.global_position.y) == int(playerPos.y) :
				inventoryManager.AddItem(itemsInWorld[i].item, 1)
				itemsInWorld[i].instance.queue_free()
				itemsInWorld.erase(itemsInWorld[i])


func AddItemToWorld(position, item: Item):
	var instance = TextureRect.new()
	instance.texture = item.icon
	instance.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	add_child(instance)
	add_to_group("Items")
	instance.position = position
	itemsInWorld.append(WorldItem.new(item, instance))
	
	
	
