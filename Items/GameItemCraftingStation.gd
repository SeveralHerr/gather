extends GameItem
class_name GameItemCraftingStation


func use(slot_data):
	PlayerManager.place_tile(slot_data)
