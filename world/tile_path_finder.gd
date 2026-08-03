extends RefCounted
class_name TilePathFinder

## Grid pathfinding over the tilemap, for anything that has to walk somewhere.
##
## AStarGrid2D rather than NavigationAgent2D, and that is a deliberate call rather than a
## preference. The tileset does carry navigation polygons, but only on layer 0 (ground)
## tiles — wall tiles have none. Godot's TileMap navigation *adds* walkable area rather than
## subtracting it, so a nav agent walks straight through a player-built wall. Making a
## navmesh respect walls would mean re-authoring every ground tile to carve out the area
## under a building. The world is already a grid of 16px cells with walls as whole cells, so
## A* over those cells is both the smaller change and the exact one, and unlike a baked
## navmesh it can be unit-tested with no TileMap and no autoloads (see for_cells).

## Half-extent, in cells, of the grid built around a query. 24 gives a 49x49 window — wide
## enough to contain any errand a BoneWorker will ask for (it searches 10 cells and then has
## to path there and back) with room for a detour around a building, and small enough that a
## rebuild is 2401 cells rather than the whole bought map, which grows without limit as the
## player buys land.
const HALF_EXTENT := 24

## How long a built grid may be reused before the world is re-read. Solidity is cached
## because rebuilding per query is what makes A* expensive, but a player who just walled a
## doorway must not have workers walking through the gap that used to be there. 500ms is
## well inside a worker's chop cadence, so consecutive errands never plan off one read.
const CACHE_MS := 500

var _handler: TileMapHandler = null

## Test mode: an explicit blocked set, no TileMap involved. Null in world mode.
var _solid: Dictionary = {}
var _fixed_bounds := Rect2i()
var _from_cells := false

var _grid: AStarGrid2D = null
var _grid_region := Rect2i()
var _built_at_ms := -1

## The cell most recently forced open as a path start, so it can be restored. Untyped so
## null can mean "none"; every Vector2i is a legal cell.
var _forced_open = null


## Pathfinder over the live world.
static func for_world(handler: TileMapHandler) -> TilePathFinder:
	var f := TilePathFinder.new()
	f._handler = handler
	return f


## Pathfinder over an explicit blocked set. `solid_cells` is any iterable of Vector2i.
## This is what makes the class testable: no TileMap, no autoloads, no scene tree.
static func for_cells(bounds: Rect2i, solid_cells: Array) -> TilePathFinder:
	var f := TilePathFinder.new()
	f._from_cells = true
	f._fixed_bounds = bounds
	for c in solid_cells:
		f._solid[c] = true
	return f


## Whether a walker may stand on this cell.
##
## Three rules, and the reasons they are not main.gd:is_occupied(). That function answers
## "may something be built here", which differs in two ways that matter: it counts a tree as
## occupying (true for building, but a walker needs trees blocked yet *reachable-adjacent*,
## which is find_path_adjacent's job), and it counts every non-grass ground as occupied,
## which would wall a walker out of terrain it can plainly stand on.
func is_walkable(cell: Vector2i) -> bool:
	if _from_cells:
		return _fixed_bounds.has_point(cell) and not _solid.has(cell)

	if _handler == null or _handler.tileMap == null:
		return false
	var tile_map: TileMap = _handler.tileMap

	# 1. There has to be dry land under the cell.
	#
	#    Deliberately "layer 0 has a tile that is not water" rather than "layer 0 is
	#    GRASS_ATLAS". GRASS_ATLAS (9,17) is only what LandManager writes for *purchased*
	#    ground; the pre-baked starting island in world/tile_map.tscn is authored as source 0
	#    atlas (0,0). Testing for the bought tile therefore rejects the entire home island,
	#    which is where every worker is placed — the pathfinder returned no route at all and
	#    the worker sat in IDLE forever. Open sea is simply an absent tile.
	if tile_map.get_cell_source_id(0, cell) == -1:
		return false
	if _is_water(tile_map, cell):
		return false

	# 2. Layer 1 is objects — walls, buildings, resources. Anything there blocks...
	if tile_map.get_cell_source_id(1, cell) != -1:
		# ...except a door, which exists precisely so a wall run can be walked through. A
		# house whose door did not path would make every interior chest unreachable, which
		# is the case this whole class was written for.
		return _is_door(tile_map, cell)

	# 3. Layer 2 is floors. A floor is the inside of a building and is walked on, not
	#    around, so it is deliberately not consulted at all.
	return true


func _is_water(tile_map: TileMap, cell: Vector2i) -> bool:
	var water := GameItems.get_item(Types.Item.Water) if GameItems != null else null
	if water == null:
		return false
	return (tile_map.get_cell_source_id(0, cell) == water.tile_source_id
		and tile_map.get_cell_atlas_coords(0, cell) == water.atlas_location)


func _is_door(tile_map: TileMap, cell: Vector2i) -> bool:
	var door := GameItems.get_item(Types.Item.WoodDoor) if GameItems != null else null
	if door == null:
		return false
	return (tile_map.get_cell_source_id(1, cell) == door.tile_source_id
		and tile_map.get_cell_atlas_coords(1, cell) == door.atlas_location)


## Cell path from `from` to `to` inclusive, or an empty array when there is no route.
## Both endpoints must be walkable; a solid destination is what find_path_adjacent is for.
func find_path(from: Vector2i, to: Vector2i) -> Array[Vector2i]:
	var out: Array[Vector2i] = []
	if from == to:
		if is_walkable(from):
			out.append(from)
		return out
	# Only the DESTINATION has to be walkable. A walker can always leave the cell it is
	# standing on, and in this game it routinely is not walkable: a BoneWorker is itself a
	# layer-1 scene tile, so its own cell reads as solid and every route out of it would be
	# refused. Chests and any future placed machine that walks have the same shape.
	if not is_walkable(to):
		return out

	_ensure_grid(from, to)
	if _grid == null or not _grid.region.has_point(from) or not _grid.region.has_point(to):
		return out

	_open_start(from)

	for cell in _grid.get_id_path(from, to):
		out.append(cell)
	return out


## Path to the nearest reachable cell orthogonally adjacent to `target` — for the things a
## walker stands beside rather than on, which is every tree and every chest.
##
## Shortest wins rather than nearest-in-a-straight-line: the cell closest to the walker may
## be the one on the far side of a wall, and picking it would report a long way round as the
## best route or report nothing at all when a neighbour was trivially reachable.
func find_path_adjacent(from: Vector2i, target: Vector2i) -> Array[Vector2i]:
	var best: Array[Vector2i] = []
	for step in [Vector2i.LEFT, Vector2i.RIGHT, Vector2i.UP, Vector2i.DOWN]:
		var candidate: Vector2i = target + step
		if not is_walkable(candidate):
			continue
		var path := find_path(from, candidate)
		if path.is_empty():
			continue
		if best.is_empty() or path.size() < best.size():
			best = path
	return best


## Drop the cached grid so the next query re-reads the world. Call it after changing the
## world yourself — clearing a tree leaves a stale solid cell behind for up to CACHE_MS
## otherwise, and the walker would path around a gap that is already open.
func invalidate() -> void:
	_grid = null
	_built_at_ms = -1
	_forced_open = null


## Force the start cell open, undoing any previous forcing first. Tracked and restored
## rather than left set, because the grid is cached across queries and a stale open cell
## would quietly punch a walkable hole through a wall for whoever asked next.
func _open_start(from: Vector2i) -> void:
	if _forced_open != null and _forced_open != from:
		_grid.set_point_solid(_forced_open, not is_walkable(_forced_open))
	if not is_walkable(from):
		_grid.set_point_solid(from, false)
		_forced_open = from
	else:
		_forced_open = null


func _ensure_grid(from: Vector2i, to: Vector2i) -> void:
	var wanted := _region_for(from, to)

	var fresh := _grid != null \
		and _grid_region == wanted \
		and (_from_cells or Time.get_ticks_msec() - _built_at_ms < CACHE_MS)
	if fresh:
		return

	_grid = AStarGrid2D.new()
	_grid.region = wanted
	_grid.cell_size = Vector2(16, 16)
	# Walls are whole cells, so a diagonal step between two solid corners would let a walker
	# slip through a sealed wall run. Requiring one open orthogonal neighbour keeps diagonal
	# movement (paths stay short and look natural) without opening that hole.
	_grid.diagonal_mode = AStarGrid2D.DIAGONAL_MODE_AT_LEAST_ONE_WALKABLE
	_grid.update()

	for x in range(wanted.position.x, wanted.end.x):
		for y in range(wanted.position.y, wanted.end.y):
			var cell := Vector2i(x, y)
			if not is_walkable(cell):
				_grid.set_point_solid(cell, true)

	_grid_region = wanted
	_built_at_ms = Time.get_ticks_msec()


## The window to build. In test mode it is simply the declared bounds; in world mode it is a
## box around both endpoints, padded so A* has room to route around an obstacle instead of
## being clipped into failure by the edge of its own grid.
func _region_for(from: Vector2i, to: Vector2i) -> Rect2i:
	if _from_cells:
		return _fixed_bounds

	var lo := Vector2i(mini(from.x, to.x), mini(from.y, to.y)) - Vector2i(HALF_EXTENT, HALF_EXTENT)
	var hi := Vector2i(maxi(from.x, to.x), maxi(from.y, to.y)) + Vector2i(HALF_EXTENT, HALF_EXTENT)
	return Rect2i(lo, hi - lo + Vector2i.ONE)
