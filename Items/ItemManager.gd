extends Node
class_name ItemManager

@export var itemsInWorld= []
@export var player: Player
@export var items: Items
@export var inventoryManager: InventoryManager
@export var resource_manager: ResourceManager2
@onready var destroy_manager = $"../../DestroyManager"


@onready var sound_manager: SoundManager = $"../../SoundManager"


# Called when the node enters the scene tree for the first time.
func _ready():
	add_to_group("SaveLoad")
	add_to_group("ItemManager")
	#resource_manager.connect("resource_removed", Callable(self, "_on_resource_removed"))
	#destroy_manager.connect("destroy_removed", Callable(self, "_on_destroy_removed"))
	pass # Replace with function body.
	
func _physics_process(delta):
	for i in range(itemsInWorld.size() - 1, -1, -1):
		itemsInWorld[i].Process(delta)
			#itemsInWorld.erase(i)
			
func _on_destroy_removed(position: Vector2i, _item: GameItem):
	position = position - Vector2i(8,8)

func _on_resource_removed(position: Vector2i, resource: GameItem):
	position = position - Vector2i(8,8)
	
func AddItemToWorldByType(position, type: Types.Item):
	position = Vector2i(position.x, position.y) - Vector2i(8,8)
	var item = items.get_item(type)
	

func AddItemToWorld(position, item: GameItem):
	var rb = RigidBody2D.new()
	rb.gravity_scale = 0
	rb.mass = 1
	
	var sprite = Sprite2D.new()
	rb.add_child(sprite)
	
	sprite.texture = item.get_atlas()
	sprite.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	sprite.z_index = 4
	
	add_child(rb)
	add_to_group("Items")
	rb.position = Vector2i(position.x, position.y) + Vector2i(8,8)


	#itemsInWorld.append(WorldItem.new(item, rb, player, inventoryManager, self, sound_manager))
	
	
func saveObject() -> Dictionary:
	var world_item_data = {}
	for i in itemsInWorld.size():
		var json = {
			"itemType": itemsInWorld[i].item.type,
			"x": itemsInWorld[i].instance.position.x,
			"y": itemsInWorld[i].instance.position.y
		}
		
		world_item_data[i] = JSON.stringify(json)
	
	var dict := {
		"filepath": get_path(),
		"world_items": world_item_data
	}
	return dict
	
func loadObject(loadedDict: Dictionary) -> void:
	itemsInWorld = []
	
	for child in get_children(): 
		child.queue_free()
	
	
	for item in loadedDict.world_items.keys():
		var x = loadedDict.world_items[item]
		var json = JSON.new()
		json.parse(x)
		var node = json.get_data()
		var pos = Vector2i(node["x"], node["y"])
		var newItem = items.get_item(node["itemType"])
		
		AddItemToWorld(pos, newItem)
