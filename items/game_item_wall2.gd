extends GameItemPlaceable
class_name GameItemWall2

## Walls are the one placeable that goes through PlayerManager.place_wall (it treats an
## occupied cell differently), so this is the only reason the as_wall branch exists.


func use(slot_data):
	_place(slot_data, true)
