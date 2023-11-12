extends Node
class_name ItemManager

@export var itemsInWorld: Array[WorldItem] = []
@export var player: Player
@export var items: Items
@export var inventoryManager: InventoryManager

# Called when the node enters the scene tree for the first time.
func _ready():
	pass # Replace with function body.

func f_process(delta):
	var activation_distance = 30.0
	var move_speed = 20.0
	var playerPos = player.global_position - Vector2(8,8)

	# Use an index-based loop backwards if you plan to remove items from the list
	for i in range(itemsInWorld.size() - 1, -1, -1):
		var item_instance = itemsInWorld[i].instance
		var direction = playerPos - item_instance.global_position
		var distance = direction.length()

		if distance > 0 and distance < activation_distance:
			direction = direction.normalized()
			item_instance.global_position += direction * move_speed * delta

		# Check if the item is close enough to consider as "reached"
		if distance < move_speed * delta:
			# Assuming inventoryManager.AddItem() doesn't depend on the state of itemsInWorld
			#inventoryManager.AddItem(itemsInWorld[i].item, 1)
			item_instance.queue_free()
			itemsInWorld.erase(i)


func AddItemToWorld(position, resource: GameResource):
	var node = Node2D.new()

	var instance = TextureRect.new()
	var location = Rect2(resource.drop.atlas_location.x*16, resource.drop.atlas_location.y*16, 16, 16)
	
	var atlas_texture = AtlasTexture.new()
	atlas_texture.atlas = load("res://Resources/game_items_atlas.tres")
	atlas_texture.region = location

	instance.texture = atlas_texture
	instance.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	add_child(node)
	instance.set_script("res://WorldItem.gd")
	if instance is WorldItem:
		instance._init(resource.drop, instance, player)
	
	node.add_child(instance)
	add_to_group("Items")
	instance.position = position
	#itemsInWorld.append()
	
	
	
