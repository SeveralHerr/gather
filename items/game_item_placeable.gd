extends GameItem
class_name GameItemPlaceable

## Base for everything that turns a stack into a tile. Building scores xp, but only when
## a tile actually went down: PlayerManager.place_tile/place_wall silently do nothing
## when the target cell is occupied, and the only trace they leave behind is the
## decremented stack count. Watching that count is why every subclass routes its use()
## through _place() instead of calling PlayerManager directly.
##
## A GameItem is a plain RefCounted with no tree of its own, so the award goes through
## PlayerManager.player to reach the scene.


func use(slot_data):
	_place(slot_data, false)


func _place(slot_data, as_wall: bool) -> void:
	var before: int = slot_data.count

	if as_wall:
		PlayerManager.place_wall(slot_data)
	else:
		PlayerManager.place_tile(slot_data)

	if slot_data.count < before:
		_award_build_xp()


func _award_build_xp() -> void:
	var player = PlayerManager.player
	if player == null:
		return

	var level_up_manager := LevelUpManager.find(player)
	if level_up_manager == null:
		return

	level_up_manager.add_xp(LevelUpManager.XP_BUILD, _placed_tile_position(player))


## Centre of the cell that was just built on, in global space. get_tile_in_front_of_player
## returns the tile's top-left corner in tilemap space, so this re-centres it and lifts it
## out to global coordinates - the splash container is elsewhere in the tree.
func _placed_tile_position(player) -> Vector2:
	var handler = player.tilemap if player else null
	if handler == null or handler.tileMap == null:
		return Vector2.INF

	var corner: Vector2 = handler.get_tile_in_front_of_player()
	return handler.tileMap.to_global(corner + Vector2(8, 8))
