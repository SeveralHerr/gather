extends GameItemPlaceable
class_name GameItemWall2


func use(slot_data):
	PlayerManager.place_wall(slot_data)
