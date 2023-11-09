extends Resource
class_name InventorySlot

@export var item: Item
@export var count: int




func _init(item: Item, count: int):
	self.item = item
	self.count = count
