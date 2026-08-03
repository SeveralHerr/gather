extends RefCounted

## TilePathFinder over an explicit blocked set — no TileMap, no autoloads, no scene tree.
## That constructor exists for exactly this: the routing rules are the part worth pinning,
## and a baked navmesh could not be tested at all without a running game.

## Injected by the runner via set(); untyped, so `var x := _T.assert_eq(...)` will not
## compile and every assertion below is written `var x: String = ...`.
var _T

const BOUNDS := Rect2i(-10, -10, 21, 21)


func _finder(solid: Array) -> TilePathFinder:
	return TilePathFinder.for_cells(BOUNDS, solid)


## A vertical wall from y=-5..5 at x=0, with no way through.
func _sealed_wall() -> Array:
	var cells: Array = []
	for y in range(-5, 6):
		cells.append(Vector2i(0, y))
	return cells


## The same wall with one cell missing at y=0 — a doorway.
func _wall_with_doorway() -> Array:
	var cells: Array = []
	for y in range(-5, 6):
		if y == 0:
			continue
		cells.append(Vector2i(0, y))
	return cells


func test_a_clear_run_paths_straight_through() -> String:
	var path := _finder([]).find_path(Vector2i(-3, 0), Vector2i(3, 0))
	var found: String = _T.assert_gt(path.size(), 0, "a clear run is pathable")
	if found != "":
		return found

	var ends: String = _T.assert_eq(path[0], Vector2i(-3, 0), "path starts at `from`")
	if ends != "":
		return ends
	return _T.assert_eq(path[path.size() - 1], Vector2i(3, 0), "path ends at `to`")


func test_a_path_routes_around_a_wall_rather_than_through_it() -> String:
	# Wall spans y=-5..5, so the only way across is around one of its ends.
	var path := _finder(_sealed_wall()).find_path(Vector2i(-3, 0), Vector2i(3, 0))
	var reachable: String = _T.assert_gt(path.size(), 0, "around the wall is still reachable")
	if reachable != "":
		return reachable

	for cell in path:
		var clear: String = _T.assert_false(cell.x == 0 and absi(cell.y) <= 5,
			"path must not cross the wall, but stepped on %s" % cell)
		if clear != "":
			return clear

	# A straight run would be 7 cells; going around the end of an 11-cell wall cannot be.
	return _T.assert_gt(path.size(), 7, "routing around costs more steps than the blocked straight line")


func test_a_doorway_is_used_when_the_wall_has_one() -> String:
	var path := _finder(_wall_with_doorway()).find_path(Vector2i(-3, 0), Vector2i(3, 0))
	var reachable: String = _T.assert_gt(path.size(), 0, "a walled room with a doorway is reachable")
	if reachable != "":
		return reachable

	var used_door := false
	for cell in path:
		if cell == Vector2i(0, 0):
			used_door = true
	return _T.assert_true(used_door, "the path goes through the doorway at (0,0)")


func test_a_fully_enclosed_target_is_unreachable() -> String:
	# Ring the target so no orthogonal or diagonal step reaches it.
	var walls: Array = []
	for dx in range(-1, 2):
		for dy in range(-1, 2):
			if dx == 0 and dy == 0:
				continue
			walls.append(Vector2i(4 + dx, 4 + dy))

	var path := _finder(walls).find_path(Vector2i(-3, 0), Vector2i(4, 4))
	return _T.assert_eq(path.size(), 0, "a sealed-in target returns no path rather than a wrong one")


## Asymmetric on purpose, and the asymmetry is the point.
##
## A solid DESTINATION is refused — that is find_path_adjacent's job. A solid START is not:
## a walker can always leave the cell it occupies, and in this game it routinely occupies a
## solid one. A BoneWorker *is* a layer-1 scene tile, so its own cell reads as solid;
## requiring a walkable start refused every route out of it and left workers standing still
## forever with a tree two cells away. Runtime caught that; nothing headless did.
func test_a_solid_destination_is_refused_but_a_solid_start_is_not() -> String:
	var f := _finder([Vector2i(2, 0)])
	var into_wall := f.find_path(Vector2i(-3, 0), Vector2i(2, 0))
	var blocked: String = _T.assert_eq(into_wall.size(), 0, "cannot path onto a solid cell")
	if blocked != "":
		return blocked

	var out_of_wall := f.find_path(Vector2i(2, 0), Vector2i(-3, 0))
	var leaves: String = _T.assert_gt(out_of_wall.size(), 0, "can always walk out of the cell you stand on")
	if leaves != "":
		return leaves
	return _T.assert_eq(out_of_wall[0], Vector2i(2, 0), "the route starts where the walker stands")


## Forcing the start cell open must not survive into the next query, or one walker leaving a
## wall punches a permanent hole through it for whoever asks next off the same cached grid.
func test_forcing_a_start_open_does_not_leak_into_later_queries() -> String:
	var f := _finder(_sealed_wall())

	var leaving := f.find_path(Vector2i(0, 0), Vector2i(3, 0))
	var left: String = _T.assert_gt(leaving.size(), 0, "a walker inside the wall can leave it")
	if left != "":
		return left

	# Same grid, different query: (0,0) must be solid again, so crossing has to go around.
	var crossing := f.find_path(Vector2i(-3, 0), Vector2i(3, 0))
	for cell in crossing:
		var clear: String = _T.assert_false(cell == Vector2i(0, 0),
			"the previously-forced cell is solid again")
		if clear != "":
			return clear
	return ""


func test_a_target_outside_the_bounds_returns_no_path() -> String:
	var path := _finder([]).find_path(Vector2i(0, 0), Vector2i(500, 500))
	return _T.assert_eq(path.size(), 0, "a target off the grid returns empty, not a crash")


## Trees and chests are solid: a worker stands beside them, never on them.
func test_find_path_adjacent_lands_beside_a_solid_target() -> String:
	var target := Vector2i(4, 0)
	var path := _finder([target]).find_path_adjacent(Vector2i(-3, 0), target)
	var reachable: String = _T.assert_gt(path.size(), 0, "a solid target is reachable-adjacent")
	if reachable != "":
		return reachable

	var last: Vector2i = path[path.size() - 1]
	var beside: String = _T.assert_eq((last - target).length_squared(), 1,
		"path ends orthogonally adjacent to the target, at %s" % last)
	if beside != "":
		return beside
	return _T.assert_false(last == target, "path never ends on the target itself")


## The neighbour nearest in a straight line can be the one behind a wall. Shortest actual
## route has to win, or a worker refuses an errand it could plainly walk.
func test_find_path_adjacent_prefers_the_reachable_side_not_the_near_side() -> String:
	var target := Vector2i(4, 0)
	# Seal the approach from the west, so only the far side of the target is reachable.
	var walls: Array = [target, Vector2i(3, 0), Vector2i(3, 1), Vector2i(3, -1),
		Vector2i(4, 1), Vector2i(4, -1)]
	var path := _finder(walls).find_path_adjacent(Vector2i(-3, 0), target)
	var reachable: String = _T.assert_gt(path.size(), 0, "the far side is still reachable")
	if reachable != "":
		return reachable

	var last: Vector2i = path[path.size() - 1]
	return _T.assert_eq(last, Vector2i(5, 0), "approached from the open side, not the walled one")


func test_find_path_adjacent_with_every_side_blocked_returns_empty() -> String:
	var target := Vector2i(4, 0)
	var walls: Array = [target, Vector2i(3, 0), Vector2i(5, 0), Vector2i(4, 1), Vector2i(4, -1)]
	var path := _finder(walls).find_path_adjacent(Vector2i(-3, 0), target)
	return _T.assert_eq(path.size(), 0, "a target with no free neighbour yields no path")


func test_a_path_to_where_you_already_stand_is_just_that_cell() -> String:
	var path := _finder([]).find_path(Vector2i(1, 1), Vector2i(1, 1))
	return _T.assert_eq(path.size(), 1, "a zero-length errand is one cell, not zero and not a crash")


## Diagonal movement is allowed, but not between two solid corners — otherwise a walker
## slips through a sealed wall run diagonally and the whole point of pathing is lost.
func test_a_diagonal_step_cannot_squeeze_between_two_solid_corners() -> String:
	# Solid at (0,0) and (1,1); stepping (0,1) -> (1,0) would cut the corner between them.
	var path := _finder([Vector2i(0, 0), Vector2i(1, 1)]).find_path(Vector2i(0, 1), Vector2i(1, 0))
	var reachable: String = _T.assert_gt(path.size(), 0, "the two open cells are still connected")
	if reachable != "":
		return reachable
	return _T.assert_gt(path.size(), 2, "must go around the corner pair, not diagonally between them")


func test_is_walkable_reports_the_blocked_set() -> String:
	var f := _finder([Vector2i(2, 2)])
	var solid: String = _T.assert_false(f.is_walkable(Vector2i(2, 2)), "a blocked cell is not walkable")
	if solid != "":
		return solid

	var open: String = _T.assert_true(f.is_walkable(Vector2i(2, 3)), "an unblocked cell is walkable")
	if open != "":
		return open

	return _T.assert_false(f.is_walkable(Vector2i(500, 500)), "outside the bounds is not walkable")
