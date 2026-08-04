extends GameItem
class_name GameItemChargedSkull

## The skull a lightning-struck skeleton leaves behind (gather-8ft).
##
## Not a placeable and not a consumable: it is fitted ONTO something that already exists.
## Using it looks for the nearest bone worker or bone turret in reach and charges that,
## which makes the machine faster and — for a turret — harder-hitting.
##
## ## Why can_use() does the search
##
## `InventoryData.use_slot_data` decrements the stack around `use()`, and `can_use()` is what
## it asks first. Doing the reach test here means standing in an empty field with a skull
## selected is a no-op rather than a skull deleted for nothing — the same rule
## GameItemConsumable follows so that eating at full health does not burn the food. The
## search runs twice per use as a result, once to answer can_use and once to act; it walks a
## handful of nodes and this is a keypress, not a frame loop.


## How far the player can reach to fit a skull, in world units.
##
## 24 is a tile and a half at the game's 16px grid, which is close enough that the player has
## to walk up to the machine and stand at it. A longer reach reads as fitting a skull to
## whichever worker happened to be nearest ACROSS a wall, since nothing here traces line of
## sight; keeping it under two tiles is what makes that impossible in practice rather than
## having to check for it.
const REACH := 24.0


func _init(_atlas_location: Vector2i,
		_tile_source_id: int,
		_type: Types.Item,
		_layer: int,
		_is_placeable: bool,
		_name: String,
		_tile_atlas_location: Vector2i = Vector2i.ZERO,
		_is_scene_tile: bool = false
	):
	super(_atlas_location, _tile_source_id, _type, _layer, _is_placeable, _name, _tile_atlas_location, _is_scene_tile)


func can_use() -> bool:
	return _nearest_chargeable() != null


func use(_target):
	var machine := _nearest_chargeable()
	if machine == null:
		# can_use() already answered this, but use() is reachable on its own and a null here
		# would be a raise on the next line — inside an untyped `use`, which aborts silently.
		return

	machine.make_charged()


## The closest worker or turret in reach that is not already charged.
##
## Returns null rather than the nearest-of-anything, and the "not already charged" half is
## what makes that matter: with a charged worker standing next to an ordinary one, picking
## purely by distance would spend the skull re-charging the machine that already has one and
## report nothing. Excluding them means the skull always goes somewhere it does something.
func _nearest_chargeable() -> Node:
	var player = PlayerManager.player
	if player == null:
		return null

	var tree := player.get_tree()
	if tree == null:
		return null

	var best: Node = null
	var best_distance := REACH

	# Both live in SaveChunks; the type check is what tells them apart, and per CLAUDE.md it
	# is a type check rather than an index because an index encodes how many members the
	# group happens to have today.
	for node in tree.get_nodes_in_group("SaveChunks"):
		if not (node is BoneWorker or node is BoneTurret):
			continue
		if node.charged:
			continue

		var node_2d := node as Node2D
		if node_2d == null:
			continue

		var distance := node_2d.global_position.distance_to(player.global_position)
		if distance <= best_distance:
			best_distance = distance
			best = node

	return best
