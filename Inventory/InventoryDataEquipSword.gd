extends InventoryData
class_name InventoryDataEquipSword

func drop_slot_data(grabbed_slot_data: SlotData, index: int) -> SlotData:
	if not grabbed_slot_data.item is GameItemSword:
		return grabbed_slot_data
	
	var slot_data = inventory_slot_datas[index]
	
	var return_slot_data: SlotData
	if slot_data:
		return slot_data
	else:
		inventory_slot_datas[index] = grabbed_slot_data
		return_slot_data = slot_data
		inventory_updated.emit(self)
		return return_slot_data


func drop_single_slot_data(grabbed_slot_data: SlotData, index: int) -> SlotData:
	
	if not grabbed_slot_data.item is GameItemSword:
		return grabbed_slot_data

	var slot_data = inventory_slot_datas[index]
	
	if not slot_data:
		inventory_slot_datas[index] = grabbed_slot_data.create_single_slot_data()
		
	inventory_updated.emit(self)
	
	if grabbed_slot_data.count > 0:
		return grabbed_slot_data
	else:
		return null



func pick_up_slot_data(slot_data: SlotData) -> bool:
	for index in inventory_slot_datas.size():
		if not inventory_slot_datas[index]:
			inventory_slot_datas[index] = slot_data
			inventory_updated.emit(self)
			return true
	return false
