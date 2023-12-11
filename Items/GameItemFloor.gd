extends GameItemPlaceable
class_name GameItemFloor


func use(slot_data):
	PlayerManager.place_tile(slot_data)
