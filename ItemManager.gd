extends Node
class_name ItemManager

@export var itemsInWorld= []
@export var player: Player
@export var items: Items
@export var inventoryManager: InventoryManager

# Called when the node enters the scene tree for the first time.
func _ready():
	pass # Replace with function body.
	
func _physics_process(delta):
	for i in range(itemsInWorld.size() - 1, -1, -1):
		if itemsInWorld[i].Process(delta):
			itemsInWorld.erase(i)


func AddItemToWorld(position, item: GameItem):
	var instance = TextureRect.new()
	var location = Rect2(item.atlas_location.x*16, item.atlas_location.y*16, 16, 16)
	
	var atlas_texture = AtlasTexture.new()
	atlas_texture.atlas = load("res://Resources/game_items_atlas.tres")
	atlas_texture.region = location

	instance.texture = atlas_texture
	instance.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	
	add_child(instance)
	add_to_group("Items")
	instance.position = position

	itemsInWorld.append(WorldItem.new(item, instance, player, inventoryManager))
	
	
	
