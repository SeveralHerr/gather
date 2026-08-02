extends RefCounted

## Guards the placement rules for walls, the one placeable that asks is_occupied() a
## different question than everything else.
##
## The regression: `is_wall` was an early `return false` covering the whole function, so a
## wall ignored every rule rather than the single one it is exempt from. Walls went down on
## open water, over a standing tree or ore vein, and on top of each other — spending the
## stack each time — while every other placeable was refused correctly, which is why the
## bug survived so long (gather-llu).
##
## These drive main.gd's is_occupied() directly against a real TileMap rather than through
## PlayerManager: place_wall needs a live Player to say which cell is in front of it, and
## the rule being asserted is not the facing logic.

var _T

var handler: TileMapHandler
var tile_map: TileMap
var items: Items
var resources: Resources

const TILE_MAP_SCENE := "res://world/tile_map.tscn"

## Somewhere the generated world will never have written, so a cell is whatever the test
## put there and nothing else.
const CELL := Vector2i(4000, 4000)


func setup() -> void:
	# Autoloads are unavailable under the headless --script runner, so the registries are
	# built directly, the way test_ore_chain does it.
	items = Items.new()
	items._ready()

	resources = Resources.new()
	resources.items = items
	resources._ready()

	# The real tileset: is_occupied looks tiles back up by atlas cell + source id, so a
	# hand-built stand-in tileset would be asserting against coordinates of its own.
	tile_map = load(TILE_MAP_SCENE).instantiate()

	# tile_map.tscn declares only Ground and Resources; Floor and Highlight are added by
	# main.tscn's instance override, so a standalone instance is two layers short and
	# every layer-2 read errors out. A runtime error inside a `-> String` test still
	# returns "" and counts as a pass (gather-1t9), so without this the whole file would
	# have gone green while asserting nothing.
	while tile_map.get_layers_count() < 4:
		tile_map.add_layer(-1)

	# Not added to the tree, and _ready() deliberately never runs — it would connect
	# managers that do not exist here and generate a world. is_occupied touches only
	# `tileMap` and `resources`.
	handler = TileMapHandler.new()
	handler.tileMap = tile_map
	handler.resources = resources
	handler.items = items


## Items and Resources are Nodes, not RefCounteds, so a setup that builds one per test
## leaks it unless the teardown says otherwise.
func teardown() -> void:
	for node in [handler, tile_map, resources, items]:
		if node != null:
			node.free()
	handler = null
	tile_map = null
	resources = null
	items = null


func _make_grass(cell: Vector2i) -> void:
	tile_map.set_cell(0, cell, 4, TileMapHandler.GRASS_ATLAS)


func _wall_item() -> GameItem:
	return items.get_item(Types.Item.StoneWall)


func _place_wall(cell: Vector2i) -> void:
	var wall: GameItem = _wall_item()
	tile_map.set_cell(1, cell, wall.tile_source_id, wall.atlas_location)


## The screenshot this file was opened for: a wall built out over open ocean. Water is a
## backdrop rather than tiles, so a sea cell has no layer-0 tile at all and reads back as
## atlas (-1, -1) — not grass, and therefore not buildable.
func test_a_wall_is_refused_on_open_water() -> String:
	return _T.assert_true(
		handler.is_occupied(CELL, true, true), "wall refused on a cell with no land under it"
	)


## The coastline is autotiled sand rather than plain grass, and GRASS_ATLAS is what
## "buildable land" means for every other placeable. Walls now answer the same way.
func test_a_wall_is_refused_on_non_grass_ground() -> String:
	tile_map.set_cell(0, CELL, 4, Vector2i(0, 15))
	return _T.assert_true(handler.is_occupied(CELL, true, true), "wall refused on coastline")


## The other half of the report. A resource occupies the object layer, so building over a
## tree used to erase a gatherable node and its yield along with it.
func test_a_wall_is_refused_on_a_standing_resource() -> String:
	_make_grass(CELL)
	var tree: GameResource = resources.Get(Types.Item.Tree)
	var known: String = _T.assert_true(tree != null, "Tree is registered")
	if known != "":
		return known

	tile_map.set_cell(1, CELL, tree.tile_source_id, tree.atlas_location, tree.is_scene_tile)
	return _T.assert_true(handler.is_occupied(CELL, true, true), "wall refused on a tree")


## Placing a wall into a wall consumed the stack and rewrote the same cell, which reads in
## game as an item vanishing for nothing.
func test_a_wall_is_refused_on_another_wall() -> String:
	_make_grass(CELL)
	_place_wall(CELL)
	return _T.assert_true(handler.is_occupied(CELL, true, true), "wall refused on a wall")


## The exemption that is the whole reason walls ask separately: a floor on layer 2 blocks
## another floor but not a wall, so the player can lay a floor and build on it.
func test_a_wall_is_allowed_on_a_player_laid_floor() -> String:
	_make_grass(CELL)
	var floor_item: GameItem = items.get_item(Types.Item.StoneFloor)
	tile_map.set_cell(2, CELL, floor_item.tile_source_id, floor_item.atlas_location)

	var allowed: String = _T.assert_false(
		handler.is_occupied(CELL, true, true), "wall allowed on top of a floor"
	)
	if allowed != "":
		return allowed

	# And the exemption stays a wall exemption — a second floor on the same cell is still
	# refused, or the flag would just be the old return-false with extra steps.
	return _T.assert_true(
		handler.is_occupied(CELL, true, false), "a non-wall is still refused on that floor"
	)


## Plain grass takes a wall, so none of the above is a blanket refusal.
func test_a_wall_is_allowed_on_clear_grass() -> String:
	_make_grass(CELL)
	return _T.assert_false(handler.is_occupied(CELL, true, true), "wall allowed on clear grass")
