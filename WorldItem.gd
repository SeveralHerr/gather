extends Node2D
class_name WorldItem

@export var item: GameItem

@export var instance: TextureRect
var player: Player
var inventoryManager: InventoryManager
var item_manager: ItemManager


func _init(item: GameItem, instance: TextureRect, player: Player, inventoryManager: InventoryManager, item_manager: ItemManager):
	self.item = item
	self.instance = instance
	self.player = player
	self.inventoryManager = inventoryManager
	self.item_manager = item_manager
	
func Process(delta) -> bool:
	var activation_distance = 30.0
	var move_speed = 20.0
	var playerPos = player.global_position - Vector2(8,8)

	# Use an index-based loop backwards if you plan to remove items from the list
	var item_instance = instance
	
	if instance == null:
		return true
	
	var direction = playerPos - item_instance.global_position
	var distance = direction.length()

	if distance > 0 and distance < activation_distance:
		direction = direction.normalized()
		item_instance.global_position += direction * move_speed * delta

	# Check if the item is close enough to consider as "reached"
	if distance < move_speed * delta:
		# Assuming inventoryManager.AddItem() doesn't depend on the state of itemsInWorld
		inventoryManager.AddItem(item, 1)
		
		for i in item_manager.itemsInWorld:
			if i.instance == instance:
				item_manager.itemsInWorld.erase(i)
		
		item_instance.queue_free()
		return true
	return false
