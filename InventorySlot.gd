extends Resource
class_name InventorySlot

var item: GameItem
@export var count: int




func _init(_item: GameItem, _count: int):
	self.item = _item
	self.count = _count
