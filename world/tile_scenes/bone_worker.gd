extends StaticBody2D
class_name BoneWorker

## Automated wood farmer, assembled the same way as BoneTurret: the player places the
## unassembled bone base, captures a skull enemy with the net, and uses the resulting
## Types.Item.BoneEnemy on it. GameItemBoneEnemy.use() is what calls set_loaded().
##
## The worker WALKS. It leaves its tile, routes to a tree with TilePathFinder, fells it,
## carries the wood to a chest — around walls and in through doors, which is the entire
## reason for pathing rather than measuring straight-line reach — and returns.
##
## THE PLACED CELL IS STILL THE ANCHOR. This node is a TileMap scene tile: the cell owns the
## instance, clear_tile on that cell destroys the worker, and occupancy and placement are
## decided on it. So the node moves its own `position` and nothing else — never reparented —
## and save() reports the home anchor rather than wherever the legs currently are, so a
## reload cannot strand a worker mid-errand.
##
## Two sprites and only one visible, exactly the turret's idiom. UnloadedSprite is the
## headless base (tiles.png cell (20,2)); LoadedSprite is the four-frame chop animation
## drawn from the cells sitting next to it, (21,2)..(24,2). The animation runs only while
## the worker is actually swinging — never while walking — so a worker in transit reads as
## in transit. There are only those four frames, so there is no walk cycle and none is
## faked: a distinct walking look needs new art, not new code.

## Set by GameItemBoneEnemy once a captured skull has been dropped on the base. Nothing
## else may write it -- go through set_loaded(), which owns the sprite swap.
var loaded: bool = false

## Seconds per completed chop, and deliberately NOT the wait_time authored on WorkTimer --
## start() below overrides it, so this constant is the only number that matters and the
## reasoning can live beside it.
##
## Twice the wooden pickaxe's 2.0s power (the slowest tier in items.gd), and the worker
## rolls the tree's yield with a flat 0.0 bonus chance where even that first pickaxe can
## carry one. So a player actively swinging the worst tool in the game still out-earns a
## worker per second spent, and every tier above it does so by more. Automation is meant to
## pay for the time you are not there, not to be the better way to fell a tree.
const CHOP_SECONDS := 4.0

## Only used if the scene's WorkArea ever loses its CircleShape2D. The authored shape is the
## source of truth for reach, so the collision shape and the search radius cannot drift.
const DEFAULT_REACH := 40.0

## Pixels per second while walking, against the player's own speed in player/player.gd.
## Deliberately slower than the player: a worker that kept pace would read as a rival, and
## one that outran them would look like a bug.
const WALK_SPEED := 25.0

## How far, in cells, the worker will look for a tree or a chest — measured from its home
## tile, not from wherever it is standing, so a worker cannot wander its search window
## across the map one errand at a time and end up arbitrarily far from where it was placed.
##
## Ten cells is 160px. The camera runs at zoom 8 on a 1920x1080 window, so the visible world
## is roughly 240x135px: an errand starts and ends inside about what the player sees standing
## at the worker, which is what makes the machine legible. It also fixes the cost at 21x21
## probes per cycle however much land has been bought.
const SEARCH_CELLS := 10

## How many candidate targets, nearest first, get an actual A* query per cycle. The cell scan
## is cheap; pathing is not, and a worker walled off from a dense grove would otherwise run
## one search per tree every cycle forever.
const MAX_PATH_PROBES := 6

## The errand, as an explicit enum-and-match in this one file. Deliberately not either of the
## project's node-based state machines: player/states/state_machine.gd transitions by name
## and enemies/states/enemy_state_machine.gd by signal, they are mutually incompatible, and
## CLAUDE.md warns against carrying either outward. Five states with no per-state data do not
## need five scripts and a node each.
enum State { IDLE, TO_TREE, CHOPPING, TO_CHEST, RETURNING }

@onready var unloaded_sprite: Sprite2D = $UnloadedSprite
@onready var loaded_sprite: AnimatedSprite2D = $LoadedSprite
@onready var work_timer: Timer = $WorkTimer
@onready var work_area: Area2D = $WorkArea

## How far this worker reaches for both trees and delivery chests, read off WorkArea.
var _reach := DEFAULT_REACH

## Whether the chop animation is currently running. Distinct from `loaded`: a loaded worker
## standing in cleared grass has nothing to chop and must read as idle.
var _working := false

var _handler: TileMapHandler

## Where the worker was placed, in the TileMap's own space. Captured lazily, the first time
## the worker actually leaves — NOT in _ready(). A scene tile's transform is assigned by the
## TileMap around the time it enters the tree, so reading position in _ready() is a race, and
## a worker that has never moved is by definition standing on its own anchor anyway. Until it
## walks, _home() is simply where it is.
var _home_position := Vector2.ZERO
var _has_home := false

var _state: int = State.IDLE

## Remaining waypoints in local space, consumed front to back as the worker walks.
var _path: Array[Vector2] = []

## The tree cell being walked to; meaningful in TO_TREE and CHOPPING only.
var _target_cell := Vector2i.ZERO

## Wood in hand, waiting for a chest. Non-zero only between felling and depositing.
var _carry := 0

## One finder held for this worker's life rather than one per query: for_world() builds a
## fresh object and a fresh object rebuilds its grid, so per-probe construction would pay
## for the grid up to MAX_PATH_PROBES times a cycle. Its own cache expires well inside the
## chop cadence, so a held instance never plans two errands off one read of the world.
var _finder: TilePathFinder = null


func _ready() -> void:
	add_to_group("SaveChunks")
	add_to_group("BoneWorker")
	_reach = _work_reach()
	work_timer.timeout.connect(_on_work_timeout)
	# WorkTimer is authored with neither autostart nor a wait_time, so this is the only place
	# the cadence is set. It used to carry 3.0 and autostart, which start() silently overrode
	# — two numbers for one thing, and the one you would find first was the dead one.
	work_timer.start(CHOP_SECONDS)
	_refresh_sprites()


## Swap to the assembled unit. Idempotent: loading an already-loaded worker is a no-op
## rather than a second skull consumed, because GameItemBoneEnemy removes the stack
## itself and cannot see whether the target was already full.
func set_loaded() -> void:
	if loaded:
		return
	loaded = true
	_refresh_sprites()
	# Settle the idle/working look now instead of leaving a freshly assembled worker
	# looking wrong for the whole CHOP_SECONDS until its first timeout.
	_set_working(not _find_tree_cell().is_empty())


## The anchor: the placed cell while the worker has never left it, the remembered one after.
func _home() -> Vector2:
	return _home_position if _has_home else position


## Freeze the anchor. Called once, immediately before the first step of the first errand.
func _anchor_home() -> void:
	if not _has_home:
		_home_position = position
		_has_home = true


func _refresh_sprites() -> void:
	unloaded_sprite.visible = not loaded
	loaded_sprite.visible = loaded
	if not loaded:
		_set_working(false)


## The think tick. Movement happens every frame in _physics_process; this only ever decides
## what to do next, so a worker walking a long path costs one decision per CHOP_SECONDS
## rather than one per frame.
func _on_work_timeout() -> void:
	if not loaded:
		return

	match _state:
		State.IDLE:
			_look_for_work()
		State.CHOPPING:
			# The walk is over and a full CHOP_SECONDS has elapsed standing beside the tree.
			_finish_chop()
		_:
			# TO_TREE / TO_CHEST / RETURNING are driven by arrival, not by the clock. The tick
			# still re-checks that the errand is still worth walking: a player may have felled
			# the target tree while the worker was on its way to it.
			_revalidate_errand()


## Walk the remaining path. Deliberately _physics_process and not _process: the worker shares
## the world with physics bodies, and moving it on the render frame would let it visibly
## stutter against them at a different cadence.
func _physics_process(delta: float) -> void:
	if not loaded or _path.is_empty():
		return

	var step := WALK_SPEED * delta
	while step > 0.0 and not _path.is_empty():
		var waypoint: Vector2 = _path[0]
		var to_go := waypoint - position
		var distance := to_go.length()
		if distance <= step:
			position = waypoint
			step -= distance
			_path.remove_at(0)
		else:
			position += to_go / distance * step
			step = 0.0

	if _path.is_empty():
		_on_arrived()


## What to do on reaching the end of a path, which depends only on why we set out.
func _on_arrived() -> void:
	match _state:
		State.TO_TREE:
			# Standing beside the tree. Start the swing; the timer tick finishes it, so a chop
			# always costs a full CHOP_SECONDS rather than whatever was left on the clock.
			_state = State.CHOPPING
			_set_working(true)
			work_timer.start(CHOP_SECONDS)
		State.TO_CHEST:
			_deposit_carry()
		State.RETURNING:
			_state = State.IDLE


## Look for a tree, then a chest if already carrying. Nothing else starts an errand.
func _look_for_work() -> void:
	if _carry > 0:
		_start_delivery()
		return

	var target := _find_tree_cell()
	if target.is_empty():
		_set_working(false)
		_go_home()
		return

	var path := _path_to_adjacent(target["cell"])
	if path.is_empty():
		# Seen but not reachable — walled off, or on an island across water. Not an error;
		# just nothing to do this cycle.
		_set_working(false)
		return

	_anchor_home()
	_target_cell = target["cell"]
	_state = State.TO_TREE
	_path = path
	_set_working(false)


## Mid-errand sanity check. The world changes under a walking worker.
func _revalidate_errand() -> void:
	if _state == State.TO_TREE and not _is_tree_at(_target_cell):
		# The player felled it first. Drop the errand rather than walking to bare grass and
		# swinging at nothing.
		_path.clear()
		_state = State.IDLE
		_set_working(false)


func _finish_chop() -> void:
	_set_working(false)
	if _is_tree_at(_target_cell):
		_fell(_target_cell)
	if _carry > 0:
		_start_delivery()
	else:
		_state = State.IDLE


## Head for the nearest reachable chest that will take wood, else drop it where we stand.
func _start_delivery() -> void:
	# Plain `var`: _find_chest_cell has an untyped return so that null can mean "no chest",
	# and GDScript cannot infer a type from that.
	var chest_cell = _find_chest_cell()
	if chest_cell == null:
		_drop_carry()
		return

	var path := _path_to_adjacent(chest_cell)
	if path.is_empty():
		# Every chest is walled off. Dropping beats standing still holding wood forever.
		_drop_carry()
		return

	_anchor_home()
	_state = State.TO_CHEST
	_path = path


func _deposit_carry() -> void:
	var wood := _wood_item()
	if wood == null:
		_state = State.IDLE
		return

	for chest in _chests_in_reach():
		if chest.inventory_data == null:
			continue
		while _carry > 0 and chest.inventory_data.pick_up_slot_data(SlotData.new(wood, 1)):
			_carry -= 1
		if _carry == 0:
			break

	# The chest filled up while we walked to it, or was full on arrival. The wood still has to
	# go somewhere, and the ground is the fallback the stationary worker already used.
	if _carry > 0:
		_drop_carry()
		return

	_go_home()


func _drop_carry() -> void:
	var wood := _wood_item()
	if wood != null:
		while _carry > 0:
			PickUpManager.create_pickup(wood, position)
			_carry -= 1
	_carry = 0
	_go_home()


func _go_home() -> void:
	if position.is_equal_approx(_home()):
		_state = State.IDLE
		_path.clear()
		return

	var finder := _path_finder()
	var handler := _tile_map_handler()
	if finder == null or handler == null or handler.tileMap == null:
		# No way to plan a route home. Snapping back beats stranding the worker somewhere it
		# can never leave — the home cell is the anchor everything else is keyed on.
		position = _home()
		_state = State.IDLE
		return

	var tile_map: TileMap = handler.tileMap
	var cells := finder.find_path(
		tile_map.local_to_map(position), tile_map.local_to_map(_home()))
	if cells.is_empty():
		position = _home()
		_state = State.IDLE
		return

	_state = State.RETURNING
	_path = _waypoints(tile_map, cells)
	_path.append(_home())


## The tree this worker would chop next as {"cell": Vector2i}, or {} when nothing is in
## reach. A Dictionary rather than a Vector2i because every Vector2i is a legal cell, so
## there is no value left over to mean "none".
func _find_tree_cell() -> Dictionary:
	var handler := _tile_map_handler()
	if handler == null or handler.tileMap == null:
		return {}

	var tree := _tree_resource(handler)
	if tree == null:
		return {}

	var tile_map: TileMap = handler.tileMap
	var best := {}
	# Measured from HOME, not from the worker's current position. Anchoring the window to the
	# tile means a worker cannot creep its search area across the map one errand at a time,
	# ending up arbitrarily far from where the player put it.
	var home := tile_map.to_global(_home())
	var best_distance := float(SEARCH_CELLS * _tile_size(tile_map))

	# Resources exist in two representations and code that knew about only one is a repeat
	# bug in this project (see ResourceManager2 and main.gd:resource_node_census). Tree is a
	# plain layer-1 cell today -- is_scene_tile is set on StoneResourceTest alone -- but that
	# is a data flag in resources.gd, so the node branch is here rather than assumed away.
	if tree.is_scene_tile:
		for child in tile_map.get_children():
			if not (child is GameSceneResource) or child.resource_type != tree.type:
				continue
			var node_distance := home.distance_to(tile_map.to_global(child.position))
			if node_distance <= best_distance:
				best_distance = node_distance
				best = {"cell": tile_map.local_to_map(child.position)}
		return best

	var origin: Vector2i = tile_map.local_to_map(_home())
	var span := SEARCH_CELLS
	for dx in range(-span, span + 1):
		for dy in range(-span, span + 1):
			var cell := origin + Vector2i(dx, dy)
			# Atlas AND source. main.gd treats that pair as the identity of a placed tile,
			# and matching on the atlas alone would claim whatever any other sheet happens
			# to draw at the same coordinates.
			#
			# It also means a tree the player is mid-gather on is skipped, because that cell
			# is showing gathering_atlas_location for the duration: the worker will not
			# steal a node out from under the swing that is already paying for it.
			if tile_map.get_cell_atlas_coords(1, cell) != tree.atlas_location:
				continue
			if tile_map.get_cell_source_id(1, cell) != tree.tile_source_id:
				continue
			var distance := home.distance_to(tile_map.to_global(tile_map.map_to_local(cell)))
			if distance <= best_distance:
				best_distance = distance
				best = {"cell": cell}

	return best


## Take the tree at `cell` down and pay out its yield.
func _fell(cell: Vector2i) -> void:
	var handler := _tile_map_handler()
	if handler == null or handler.tileMap == null:
		return

	var tree := _tree_resource(handler)
	if tree == null:
		return

	# clear_tile is exactly what main.gd runs when it hears resource_removed, and it also
	# frees a scene-backed node by clearing the cell that instanced it. Going through
	# ResourceManager2.remove_resource() instead would be shorter but would award the tree's
	# xp, and automation must not reopen the xp faucet gather-5s5 just closed.
	handler.clear_tile(cell)

	# tree.drop, not a hardcoded Types.Item.Wood: what a tree yields is already stated once,
	# in the resources.gd registration, and a second copy here would be the one that goes
	# stale. This unit is a wood farmer because trees drop wood, not the other way round.
	var wood := GameItems.get_item(tree.drop)
	if wood == null:
		return

	# The world just changed under the pathfinder: the felled cell is walkable now, and the
	# cached grid still says otherwise. Without this the worker routes around a tree it took
	# down itself for up to the finder's cache window.
	if _finder != null:
		_finder.invalidate()

	# roll_yield with no bonus argument: bonus_yield_chance belongs to the pickaxe in the
	# player's hand and to the Bountiful Harvest skill, and a worker holds neither. The
	# 1..2 range itself is the tree's own, from Resources.TUNING.
	#
	# The wood goes into _carry rather than straight to a chest: the whole point of walking is
	# that the chest is somewhere else. _start_delivery decides where it ends up.
	_carry += tree.roll_yield()

	# The secondary Food drop is deliberately not rolled. It is the forager's bonus for
	# working the tree by hand; a worker farm that also fed the player would make the one
	# consumable in the game free.


## The item a felled tree yields, or null when the registry is not up (headless tests).
func _wood_item() -> GameItem:
	var handler := _tile_map_handler()
	if handler == null:
		return null
	var tree := _tree_resource(handler)
	if tree == null or GameItems == null:
		return null
	return GameItems.get_item(tree.drop)


## Whether the tree this worker set out for is still standing. Matched on atlas AND source,
## the same pair main.gd treats as a placed tile's identity.
func _is_tree_at(cell: Vector2i) -> bool:
	var handler := _tile_map_handler()
	if handler == null or handler.tileMap == null:
		return false
	var tree := _tree_resource(handler)
	if tree == null:
		return false
	var tile_map: TileMap = handler.tileMap
	return (tile_map.get_cell_atlas_coords(1, cell) == tree.atlas_location
		and tile_map.get_cell_source_id(1, cell) == tree.tile_source_id)


## The cell of the nearest chest that will currently take wood, or null when there is none.
## Returns a cell rather than the node because the caller paths to it, and a chest is solid:
## the worker stands beside it.
func _find_chest_cell():
	var handler := _tile_map_handler()
	if handler == null or handler.tileMap == null:
		return null
	var tile_map: TileMap = handler.tileMap
	var home := tile_map.to_global(_home())
	var limit := float(SEARCH_CELLS * _tile_size(tile_map))

	var best = null
	var best_distance := limit
	for node in get_tree().get_nodes_in_group("external_inventory"):
		# Type-checked rather than indexed: the group carries whatever else opts into an
		# external inventory later, and indexing a group is a documented past bug here.
		if not (node is TestChest):
			continue
		var chest := node as TestChest
		if not _chest_has_room(chest):
			continue
		var distance := home.distance_to(chest.global_position)
		if distance <= best_distance:
			best_distance = distance
			best = tile_map.local_to_map(tile_map.to_local(chest.global_position))
	return best


## Whether a chest could take at least one more wood: a free slot, or a wood stack with room.
## Checked before walking rather than on arrival so a full chest does not win the "nearest"
## contest and send the worker on a pointless errand every cycle.
func _chest_has_room(chest: TestChest) -> bool:
	if chest.inventory_data == null:
		return false
	var wood := _wood_item()
	for slot in chest.inventory_data.inventory_slot_datas:
		if slot == null:
			return true
		if wood != null and slot.item != null and slot.item.type == wood.type:
			return true
	return false


## Delivery chests within reach, nearest first.
func _chests_in_reach() -> Array[TestChest]:
	var found: Array[TestChest] = []
	for node in get_tree().get_nodes_in_group("external_inventory"):
		# Type-checked rather than indexed: the group carries whatever else opts into an
		# external inventory later, and indexing a group is a documented past bug here.
		if node is TestChest and global_position.distance_to(node.global_position) <= _reach:
			found.append(node as TestChest)

	var origin := global_position
	found.sort_custom(func(a: TestChest, b: TestChest) -> bool:
		return origin.distance_squared_to(a.global_position) < origin.distance_squared_to(b.global_position))
	return found


## The animation is the only thing that tells a player whether a worker still has anything
## to do, so it tracks the target rather than `loaded`. Re-evaluated once per work cycle
## rather than per frame -- the scan above is cheap but not free, and there can be one of
## these on every buildable tile.
func _set_working(working: bool) -> void:
	if _working == working:
		return
	_working = working
	if working:
		loaded_sprite.play("chop")
	else:
		loaded_sprite.stop()


## The finder, built once and kept. Dropped whenever the handler is re-resolved.
func _path_finder() -> TilePathFinder:
	var handler := _tile_map_handler()
	if handler == null:
		return null
	if _finder == null:
		_finder = TilePathFinder.for_world(handler)
	return _finder


## A walk to a cell beside `cell`, as local-space waypoints. Empty when unreachable.
func _path_to_adjacent(cell: Vector2i) -> Array[Vector2]:
	var empty: Array[Vector2] = []
	var finder := _path_finder()
	var handler := _tile_map_handler()
	if finder == null or handler == null or handler.tileMap == null:
		return empty

	var tile_map: TileMap = handler.tileMap
	var cells := finder.find_path_adjacent(tile_map.local_to_map(position), cell)
	if cells.is_empty():
		return empty
	return _waypoints(tile_map, cells)


## Cell path to walkable positions. Cell centres, not corners: map_to_local gives the centre
## in this project's tileset, and walking to corners would clip the worker into wall edges.
func _waypoints(tile_map: TileMap, cells: Array[Vector2i]) -> Array[Vector2]:
	var out: Array[Vector2] = []
	for c in cells:
		out.append(tile_map.map_to_local(c))
	return out


## The tileset's cell size, floored at one so a degenerate value cannot produce a zero-width
## search window. Read off the tileset rather than assuming 16px.
func _tile_size(tile_map: TileMap) -> int:
	if tile_map.tile_set == null:
		return 16
	return maxi(1, mini(tile_map.tile_set.tile_size.x, tile_map.tile_set.tile_size.y))


func _tile_map_handler() -> TileMapHandler:
	if _handler != null and is_instance_valid(_handler):
		return _handler
	for node in get_tree().get_nodes_in_group("TileMapHandler"):
		if node is TileMapHandler:
			_handler = node
			return _handler
	return null


## Looked up through get_item_or_resource_by_type rather than Resources.Get, which indexes
## its dictionary directly and errors on a type that is not registered yet.
func _tree_resource(handler: TileMapHandler) -> GameResource:
	if handler.resources == null:
		return null
	var entry := handler.resources.get_item_or_resource_by_type(Types.Item.Tree)
	return entry as GameResource


func _work_reach() -> float:
	var shape_node := work_area.get_node_or_null("CollisionShape2D") as CollisionShape2D
	if shape_node != null and shape_node.shape is CircleShape2D:
		return (shape_node.shape as CircleShape2D).radius
	return DEFAULT_REACH


## How many cells out the tile scan has to walk to cover _reach. Read off the tileset rather
## than assuming 16px, and floored at one so a degenerate tile size cannot produce a scan
## that looks at nothing.
func _cell_span(tile_map: TileMap) -> int:
	var tile_size := 16
	if tile_map.tile_set != null:
		tile_size = maxi(1, mini(tile_map.tile_set.tile_size.x, tile_map.tile_set.tile_size.y))
	return maxi(1, int(ceil(_reach / float(tile_size))))


## SaveChunks contract. "filepath" keys the scene the loader rebuilds this from, matching
## BoneTurret's dict shape so main.gd's chunk loader needs no special case.
## Reports the HOME anchor, never the live position. SaveLoad.late_load() matches a saved
## chunk back onto a node by comparing x/y, and the cell is what placement and occupancy are
## keyed on — so a worker saved mid-errand must still describe its tile, not its legs.
func save() -> Dictionary:
	return {
		"x": _home().x,
		"y": _home().y,
		"data": {"loaded": loaded},
		"filepath": "343",
	}


## Every value here arrives from JSON.parse of a file on disk, so nothing about its shape is
## guaranteed — a save from an older build, or one edited by hand, can put any type in any
## slot. Each level is therefore type-checked before it is read.
##
## The `loaded` check in particular is a typeof and not `== true`: comparing a String to a
## bool raises "Invalid operands" rather than evaluating false, which would abort the load
## partway and leave the worker at the origin with its state dropped — the silent
## save-corruption failure CLAUDE.md calls out. It also would not have failed the suite,
## because a runtime error inside a `-> String` test still returns "" and counts as a pass
## (gather-1t9).
func load(dict) -> void:
	if typeof(dict) != TYPE_DICTIONARY:
		return

	var data = dict.get("data")
	if typeof(data) != TYPE_DICTIONARY:
		return

	if typeof(data.get("loaded")) == TYPE_BOOL and data["loaded"]:
		set_loaded()
