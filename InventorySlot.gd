extends Resource
class_name InventorySlot

var item: GameItem
@export var count: int




func _init(item: GameItem, count: int):
	self.item = item
	self.count = count
