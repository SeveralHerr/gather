extends Resource
class_name InventoryData

signal inventory_updated(inventory_data: InventoryData)
signal inventory_interact(inventory_data: InventoryData, index: int, button: int )

@export var inventory_slot_datas: Array[SlotData] = []


func get_count(item: GameItem):
	for i in inventory_slot_datas.size():
		var data = inventory_slot_datas[i]
		if data and data.item == item:
			return data.count
	return 0
			
func has_item(item: GameItem):
	for i in inventory_slot_datas.size():
		var data = inventory_slot_datas[i]
		if data and data.item == item:
			return true
	return false
	
func has_items(item: GameItem, amount_to_craft: int):
	for i in range(inventory_slot_datas.size()):
		var data = inventory_slot_datas[i]
		if data and data.item.type == item.type and amount_to_craft <= data.count:
			return true
	return false
	
func remove(item: GameItem):
	for i in inventory_slot_datas.size():
		var data = inventory_slot_datas[i]
		if data and data.item == item:
			data.count -= 1
			if data.count <= 0:
				inventory_slot_datas[i] = null
				
			inventory_updated.emit(self)
			return
	
## Total held across every slot. get_count() compares GameItem identity and stops at
## the first slot, so it answers a different question: this one is what a price check
## needs when a currency has spilled into more than one stack.
func count_of_type(type: Types.Item) -> int:
	var total := 0
	for data in inventory_slot_datas:
		if data and data.item and data.item.type == type:
			total += data.count
	return total


## Spends `amount` of `type`, draining partial stacks in slot order. Returns false
## and removes nothing when the player cannot afford it, so a caller never has to
## unwind a half-completed payment.
func spend_type(type: Types.Item, amount: int) -> bool:
	if amount <= 0 or count_of_type(type) < amount:
		return false

	var remaining := amount
	for index in inventory_slot_datas.size():
		if remaining <= 0:
			break
		var data = inventory_slot_datas[index]
		if not data or not data.item or data.item.type != type:
			continue

		var taken: int = mini(remaining, data.count)
		data.count -= taken
		remaining -= taken
		if data.count <= 0:
			inventory_slot_datas[index] = null

	inventory_updated.emit(self)
	return true


## Whether `cost_list` (a CraftingRecipe cost dict, Types.Item -> per-unit amount) is
## affordable `multiplier` times over. Counts across every stack, which is the whole
## reason this exists: has_items() stops at the first matching slot, so a player
## holding 3 + 3 wood in two slots reads as unable to afford 5.
func can_afford(cost_list: Dictionary, multiplier: int = 1) -> bool:
	if multiplier <= 0:
		return false
	for type in cost_list:
		if count_of_type(type) < int(cost_list[type]) * multiplier:
			return false
	return true


## Pays `cost_list` `multiplier` times over, all-or-nothing. Every key is checked
## before anything is removed, so a caller never has to unwind a half-paid recipe —
## the failure mode the old per-key remove() loop had no way to avoid.
func spend_cost(cost_list: Dictionary, multiplier: int = 1) -> bool:
	if not can_afford(cost_list, multiplier):
		return false
	for type in cost_list:
		spend_type(type, int(cost_list[type]) * multiplier)
	return true


## How many times over `cost_list` could be paid right now. Drives the "x12" badge on
## a recipe card and the MAX button; 0 means the recipe is visible but unaffordable.
func affordable_count(cost_list: Dictionary) -> int:
	if cost_list.is_empty():
		return 0
	var best := -1
	for type in cost_list:
		var per_unit := int(cost_list[type])
		if per_unit <= 0:
			continue
		var possible := count_of_type(type) / per_unit
		if best < 0 or possible < best:
			best = possible
	return maxi(best, 0)


func remove_by_type(type: Types.Item):
	for i in inventory_slot_datas.size():
		var data = inventory_slot_datas[i]
		if data and data.item.type == type:
			data.count -= 1
			if data.count <= 0:
				inventory_slot_datas[i] = null
				
			inventory_updated.emit(self)
			return
				

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
		
func stop_slot_data(index: int):
	var slot_data = inventory_slot_datas[index]
	
	if not slot_data:
		return	
		
	PlayerManager.stop_slot_data(slot_data)
	
func use_slot_data(index: int):
	var slot_data = inventory_slot_datas[index]
	
	if not slot_data:
		return	
	
	if slot_data.item is GameItemConsumable: # or slot_data.item is GameItemCraftingStation:
		if not slot_data.item.can_use():
			return
		slot_data.count -= 1

	PlayerManager.use_slot_data(slot_data)

	if slot_data.count < 1:
		inventory_slot_datas[index] = null
	inventory_updated.emit(self)
	
func show_slot_data(index: int):
	var slot_data = inventory_slot_datas[index]
	
	if not slot_data:
		return	
		
	PlayerManager.show_slot_data(slot_data)
	
func inv_updated():
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
