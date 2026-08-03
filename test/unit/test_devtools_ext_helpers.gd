extends RefCounted

## Headless coverage for the pure halves of the devtools nearest-cell search
## (gather-7y9 / G-037a): TileMapHandler.cells_within enumerates the candidates and
## cell_nearest_to picks the winner. The occupancy filter between them needs a live
## tilemap, so it is runtime-only and deliberately not covered here.

var _T


func test_cells_within_covers_the_square_minus_origin() -> String:
	var offsets: Array = TileMapHandler.cells_within(2)

	var r: String = _T.assert_eq(offsets.size(), 24, "5x5 square minus the origin")
	if r != "":
		return r
	r = _T.assert_false(offsets.has(Vector2i.ZERO), "the player's own cell is excluded")
	if r != "":
		return r
	r = _T.assert_true(offsets.has(Vector2i(-2, -2)), "the far corner is included")
	if r != "":
		return r
	return _T.assert_true(offsets.has(Vector2i(1, 0)), "the adjacent cell is included")


func test_cells_within_radius_matches_old_ring_reach() -> String:
	# The verbs used to scan rings 1..7; the helper must reach exactly as far.
	var offsets: Array = TileMapHandler.cells_within(7)
	var r: String = _T.assert_eq(offsets.size(), 15 * 15 - 1, "full 15x15 neighbourhood")
	if r != "":
		return r
	return _T.assert_true(offsets.has(Vector2i(7, -7)), "the outermost ring is reachable")


func test_nearest_cell_prefers_adjacent_over_ring_corner() -> String:
	# The G-037a symptom: the old scan visited (-ring,-ring) first, so a station landed
	# 48px away on the far corner. Nearest-first must pick a distance-1 cell instead.
	var origin := Vector2i(10, 10)
	var free := []
	for offset in TileMapHandler.cells_within(3):
		free.append(origin + offset)

	var nearest = TileMapHandler.cell_nearest_to(free, origin)
	var r: String = _T.assert_true(nearest != null, "a cell was found")
	if r != "":
		return r
	return _T.assert_float_eq(
		Vector2(nearest - origin).length(), 1.0, 0.001,
		"the nearest free cell is directly adjacent")


func test_nearest_cell_skips_to_second_ring_when_first_is_occupied() -> String:
	# Only cells at Chebyshev distance >= 2 offered: the winner must be an axis cell of
	# the second ring (euclidean 2.0), never its corner (2.83).
	var origin := Vector2i.ZERO
	var free := []
	for offset in TileMapHandler.cells_within(3):
		if maxi(absi(offset.x), absi(offset.y)) >= 2:
			free.append(origin + offset)

	var nearest = TileMapHandler.cell_nearest_to(free, origin)
	var r: String = _T.assert_true(nearest != null, "a cell was found")
	if r != "":
		return r
	return _T.assert_float_eq(
		Vector2(nearest - origin).length(), 2.0, 0.001,
		"the winner sits on the second ring's axis")
