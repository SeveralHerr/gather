extends StaticBody2D
class_name BoneWorker

## Automated wood farmer, assembled the same way as BoneTurret: the player places the
## unassembled bone base, captures a skull enemy with the net, and uses the resulting
## Types.Item.BoneEnemy on it. GameItemBoneEnemy.use() is what calls set_loaded().
##
## Two sprites and only one visible, exactly the turret's idiom. UnloadedSprite is the
## headless base (tiles.png cell (20,2)); LoadedSprite is the four-frame chop animation
## drawn from the cells sitting next to it, (21,2)..(24,2). The animation runs only while
## the worker is actually chopping, so a loaded-but-idle worker reads as idle.

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


func _refresh_sprites() -> void:
	unloaded_sprite.visible = not loaded
	loaded_sprite.visible = loaded
	if not loaded:
		_set_working(false)


## One work cycle: find a tree in reach, fell it, and put the wood somewhere.
func _on_work_timeout() -> void:
	if not loaded:
		return

	var target := _find_tree_cell()
	if target.is_empty():
		_set_working(false)
		return

	_set_working(true)
	_fell(target["cell"])


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
	var best_distance := _reach

	# Resources exist in two representations and code that knew about only one is a repeat
	# bug in this project (see ResourceManager2 and main.gd:resource_node_census). Tree is a
	# plain layer-1 cell today -- is_scene_tile is set on StoneResourceTest alone -- but that
	# is a data flag in resources.gd, so the node branch is here rather than assumed away.
	if tree.is_scene_tile:
		for child in tile_map.get_children():
			if not (child is GameSceneResource) or child.resource_type != tree.type:
				continue
			var node_distance := global_position.distance_to(tile_map.to_global(child.position))
			if node_distance <= best_distance:
				best_distance = node_distance
				best = {"cell": tile_map.local_to_map(child.position)}
		return best

	var origin: Vector2i = tile_map.local_to_map(tile_map.to_local(global_position))
	var span := _cell_span(tile_map)
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
			var distance := global_position.distance_to(tile_map.to_global(tile_map.map_to_local(cell)))
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

	var tile_map: TileMap = handler.tileMap
	# Tilemap-local, which is the space PickUpManager.create() drops into: PickUps is a
	# sibling of TileMap under World, and ResourceManager2.remove_resource() hands it the
	# same map_to_local() value.
	var drop_position := tile_map.map_to_local(cell)

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

	# roll_yield with no bonus argument: bonus_yield_chance belongs to the pickaxe in the
	# player's hand and to the Bountiful Harvest skill, and a worker holds neither. The
	# 1..2 range itself is the tree's own, from Resources.TUNING.
	for _i in tree.roll_yield():
		_deliver(wood, drop_position)

	# The secondary Food drop is deliberately not rolled. It is the forager's bonus for
	# working the tree by hand; a worker farm that also fed the player would make the one
	# consumable in the game free.


## One wood, into the nearest chest that will take it, otherwise onto the ground.
func _deliver(wood: GameItem, drop_position: Vector2) -> void:
	for chest in _chests_in_reach():
		if chest.inventory_data == null:
			continue
		# pick_up_slot_data merges into a matching stack first and only then claims a free
		# slot, which is precisely the delivery order wanted here, and it is the same call
		# the player's own pickups go through.
		if chest.inventory_data.pick_up_slot_data(SlotData.new(wood, 1)):
			return

	PickUpManager.create_pickup(wood, drop_position)


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
func save() -> Dictionary:
	return {
		"x": position.x,
		"y": position.y,
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
