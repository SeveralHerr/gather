extends GameItem
class_name GameItemPlaceable

## Base for everything that turns a stack into a tile.
##
## This used to score xp for a placement, which is why the class existed at all: the award had
## to fire only when a tile ACTUALLY went down, and PlayerManager.place_tile/place_wall report
## an occupied cell by silently doing nothing except leaving the stack count alone. Watching
## that count was the reason every subclass routed its use() through _place() rather than
## calling PlayerManager directly.
##
## Placing pays nothing now (see LevelUpManager's award table for why), so what is left here is
## the wall-versus-tile branch — the one thing GameItemWall2 needs and nothing else does.
##
## The count check survives in GameItemBerryBush.use(), which needs the same "did it land"
## answer for a different reason: it marks the cell as planted, and marking a cell no bush went
## onto would leak a claim onto the next bush that grows there.


func use(slot_data):
	_place(slot_data, false)


func _place(slot_data, as_wall: bool) -> void:
	if as_wall:
		PlayerManager.place_wall(slot_data)
	else:
		PlayerManager.place_tile(slot_data)


## The tilemap cell that was just built on. Untyped return: null means there is no tilemap
## to ask.
##
## get_tile_in_front_of_player() hands back that cell already converted to a local pixel
## corner, so this converts it straight back rather than duplicating the facing logic —
## two implementations of "the cell in front" that could disagree is exactly how a bush's
## planted mark would end up keyed on a different square than the one the bush went onto.
func _placed_cell(player):
	var handler = player.tilemap if player else null
	if handler == null or handler.tileMap == null:
		return null

	return handler.tileMap.local_to_map(handler.get_tile_in_front_of_player() + Vector2(8, 8))
