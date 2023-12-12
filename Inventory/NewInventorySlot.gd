extends Resource
class_name SlotData

var item: GameItem
@export var count: int = 1: set = set_quantity



func _init(_item: GameItem = null, _count: int = 0):
	self.item = _item
	self.count = _count

func set_quantity(quantity: int) -> void: 
	count = quantity
	
func can_fully_merge_with(other_slot_data: SlotData) -> bool:
	return item.type == other_slot_data.item.type

func fully_merge_with(other_slot_data: SlotData) -> void:
	count += other_slot_data.count

func create_single_slot_data() -> SlotData:
	var new_slot_data = duplicate()
	new_slot_data.item = item
	new_slot_data.count = 1
	count -= 1
	return new_slot_data
