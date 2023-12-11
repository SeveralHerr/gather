extends GameItem
class_name GameItemPlaceable


func use(slot_data):
	PlayerManager.place_tile(slot_data)
