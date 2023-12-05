extends Resource
class_name InventoryData

signal inventory_updated(inventory_data: InventoryData)
signal inventory_interact(inventory_data: InventoryData, index: int, button: int )

@export var inventory_slot_datas: Array[SlotData] = []

func on_slot_clicked(index: int, button: int) -> void:
	inventory_interact.emit(self, index, button)

func grab_slot_data(index: int) -> SlotData:
	var slot_data = inventory_slot_datas[index]
	
	if slot_data:
		inventory_slot_datas[index] = null
		inventory_updated.emit(self)
		return slot_data
	else:
		return null
	
func use_slot_data(index: int):
	var slot_data = inventory_slot_datas[index]
	
	if not slot_data:
		return	
	
	if slot_data.item is GameItemConsumable:
		slot_data.count -= 1
		if slot_data.count < 1:
			inventory_slot_datas[index] = null
	
	PlayerManager.use_slot_data(slot_data)
	
	inventory_updated.emit(self)
		
func drop_slot_data(grabbed_slot_data: SlotData, index: int) -> SlotData:
	var slot_data = inventory_slot_datas[index]
	
	var return_slot_data: SlotData
	if slot_data and slot_data.can_fully_merge_with(grabbed_slot_data):
		slot_data.fully_merge_with(grabbed_slot_data)
	else:
		inventory_slot_datas[index] = grabbed_slot_data
		return_slot_data = slot_data
		
	inventory_updated.emit(self)
	return return_slot_data
		
func drop_single_slot_data(grabbed_slot_data: SlotData, index: int) -> SlotData:
	var slot_data = inventory_slot_datas[index]
	
	if not slot_data:
		inventory_slot_datas[index] = grabbed_slot_data.create_single_slot_data()
	elif slot_data.can_fully_merge_with(grabbed_slot_data):
		slot_data.fully_merge_with(grabbed_slot_data.create_single_slot_data())
		
	inventory_updated.emit(self)
	
	if grabbed_slot_data.count > 0:
		return grabbed_slot_data
	else:
		return null
		
func pick_up_slot_data(slot_data: SlotData) -> bool:
	for index in inventory_slot_datas.size():
		if inventory_slot_datas[index] and inventory_slot_datas[index].can_fully_merge_with(slot_data)  :
			inventory_slot_datas[index].fully_merge_with(slot_data)
			inventory_updated.emit(self)
			return true
	
	for index in inventory_slot_datas.size():
		if not inventory_slot_datas[index]:
			inventory_slot_datas[index] = slot_data
			inventory_updated.emit(self)
			return true
	return false
