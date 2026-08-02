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

	# Per cell, not per placement: DestroyManager hands the tile back as a pickup, so
	# paying every time made place/destroy/repeat on one square an xp faucet that consumed
	# nothing. See LevelUpManager.built_cells (gather-5s5).
	# Plain `var`, not `:=` — _placed_cell has an untyped return so that null can mean
	# "no tilemap", and GDScript cannot infer a type from that.
	var cell = _placed_cell(player)
	if cell == null:
		return

	level_up_manager.award_build_xp(cell, _placed_tile_position(player))


## The tilemap cell that was just built on. Untyped return: null means there is no tilemap
## to ask, which is the same guard _placed_tile_position makes.
##
## get_tile_in_front_of_player() hands back that cell already converted to a local pixel
## corner, so this converts it straight back rather than duplicating the facing logic —
## two implementations of "the cell in front" that could disagree is exactly how the xp
## ledger would end up keyed on a different square than the one the tile went onto.
func _placed_cell(player):
	var handler = player.tilemap if player else null
	if handler == null or handler.tileMap == null:
		return null

	return handler.tileMap.local_to_map(handler.get_tile_in_front_of_player() + Vector2(8, 8))


## Centre of the cell that was just built on, in global space. get_tile_in_front_of_player
## returns the tile's top-left corner in tilemap space, so this re-centres it and lifts it
## out to global coordinates - the splash container is elsewhere in the tree.
func _placed_tile_position(player) -> Vector2:
	var handler = player.tilemap if player else null
	if handler == null or handler.tileMap == null:
		return Vector2.INF

	var corner: Vector2 = handler.get_tile_in_front_of_player()
	return handler.tileMap.to_global(corner + Vector2(8, 8))
