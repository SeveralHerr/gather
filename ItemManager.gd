extends Node
class_name ItemManager

@export var itemsInWorld= []
@export var player: Player
@export var items: Items
@export var inventoryManager: InventoryManager
@export var resource_manager: ResourceManager2

# Called when the node enters the scene tree for the first time.
func _ready():
	add_to_group("SaveLoad")
	add_to_group("ItemManager")
	resource_manager.connect("resource_removed", Callable(self, "_on_resource_removed"))
	pass # Replace with function body.
	
func _physics_process(delta):
	for i in range(itemsInWorld.size() - 1, -1, -1):
		itemsInWorld[i].Process(delta)
			#itemsInWorld.erase(i)

func _on_resource_removed(position: Vector2i, resource: GameResource):
	position = position - Vector2i(8,8)
	AddItemToWorld(position, resource.drop)
	
func AddItemToWorldByType(position, type: GameItem.Type):
	position = Vector2i(position.x, position.y) - Vector2i(8,8)
	var item = items.Get(type)
	AddItemToWorld(position, item)
	

func AddItemToWorld(position, item: GameItem):
	var instance = TextureRect.new()
	var location = Rect2(item.atlas_location.x*16, item.atlas_location.y*16, 16, 16)
	
	var atlas_texture = AtlasTexture.new()
	atlas_texture.atlas = load("res://Resources/game_items_atlas.tres")
	atlas_texture.region = location

	instance.texture = atlas_texture
	instance.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	instance.z_index = 4
	
	add_child(instance)
	add_to_group("Items")
	instance.position = position

	itemsInWorld.append(WorldItem.new(item, instance, player, inventoryManager, self))
	
	
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
		var newItem = items.Get(node["itemType"])
		
		AddItemToWorld(pos, newItem)
