extends RefCounted

## Guards the stone wall / stone floor set, which is spread across five files that
## have no compile-time link to each other: the art sheet, the tileset source, the
## item registrations in items.gd, the recipes, and main.gd's WALL_TYPES table. The
## dangerous edit is a coordinate one - every one of these agrees on atlas cells by
## convention only, and getting one wrong produces a wall that places as a single
## unconnected tile, or a floor that the game classifies as a wall, with nothing
## anywhere reporting an error.

var _T

var items: Items
var recipes

const STONE_SET := [Types.Item.StoneWall, Types.Item.StoneFloor]


func setup() -> void:
	# Autoloads are unavailable under the headless --script runner, so the registries
	# are built directly, the way test_ore_chain and test_progression do it.
	items = Items.new()
	items._ready()

	recipes = load("res://crafting/recipes.gd").new()
	recipes.furnace_recipes()
	recipes.sawmill_recipes()


func _stone_wall_type() -> Dictionary:
	for wall in TileMapHandler.WALL_TYPES:
		if wall["item"] == Types.Item.StoneWall:
			return wall
	return {}


## Both halves of the set exist, on the generated stone sheet rather than on whatever
## source happened to be inherited from the wood item they were copied from.
func test_stone_items_are_registered_on_the_stone_sheet() -> String:
	for type in STONE_SET:
		var item: GameItem = items.get_item(type)
		var missing: String = _T.assert_true(item != null, "item registered for %d" % type)
		if missing != "":
			return missing

		var source: String = _T.assert_eq(
			item.tile_source_id, GameItem.STONE_BUILD_SOURCE_ID, "%s tile source" % item.name
		)
		if source != "":
			return source
	return ""


## main.gd resets a wall run to WALL_TYPES.base before re-solving the joins, and
## looks the item up by that same cell when the player destroys one. If the table and
## the registration disagree, a placed stone wall becomes undestroyable - the lookup
## in get_location_of_nearby_item_to_destroy matches nothing.
func test_wall_table_agrees_with_the_registered_wall_item() -> String:
	var wall := _stone_wall_type()
	var present: String = _T.assert_false(wall.is_empty(), "StoneWall has a WALL_TYPES entry")
	if present != "":
		return present

	var item: GameItem = items.get_item(Types.Item.StoneWall)
	var base: String = _T.assert_eq(wall["base"], item.atlas_location, "stone wall base cell")
	if base != "":
		return base

	return _T.assert_eq(wall["source"], item.tile_source_id, "stone wall atlas source")


## The blob's own top-left cell has to be inside the rect that identifies it, or a
## freshly placed wall is not recognised as a wall at all.
func test_every_wall_base_is_inside_its_own_rect() -> String:
	for wall in TileMapHandler.WALL_TYPES:
		var inside: String = _T.assert_true(
			wall["rect"].has_point(wall["base"]),
			"%s base %s inside rect %s" % [wall["item"], wall["base"], wall["rect"]]
		)
		if inside != "":
			return inside
	return ""


## The two wall types must never claim the same cell, or a wood wall and a stone wall
## autotile into each other and the save writes back the wrong item.
func test_wall_rects_do_not_overlap_within_a_source() -> String:
	for a in TileMapHandler.WALL_TYPES:
		for b in TileMapHandler.WALL_TYPES:
			if a["item"] == b["item"]:
				continue
			if a["source"] != b["source"]:
				continue
			var clear: String = _T.assert_false(
				a["rect"].intersects(b["rect"]),
				"%s and %s share source %d and overlap" % [a["item"], b["item"], a["source"]]
			)
			if clear != "":
				return clear

	# Distinct terrains matter as much as distinct rects: same terrain index would let
	# set_cells_terrain_connect join the two runs even from separate sheets.
	var terrains := {}
	for wall in TileMapHandler.WALL_TYPES:
		var unique: String = _T.assert_false(
			terrains.has(wall["terrain"]), "terrain %d used twice" % wall["terrain"]
		)
		if unique != "":
			return unique
		terrains[wall["terrain"]] = true
	return ""


## The regression this file exists for. The stone floor lives on the same sheet as the
## stone wall blob, and main.gd classifies a wall by source + rect - so a floor placed
## inside that rect would be appended to the wall run, autotiled on layer 1, and saved
## back as a wall.
func test_stone_floor_is_not_inside_the_wall_rect() -> String:
	var wall := _stone_wall_type()
	var present: String = _T.assert_false(wall.is_empty(), "StoneWall has a WALL_TYPES entry")
	if present != "":
		return present

	var floor_item: GameItem = items.get_item(Types.Item.StoneFloor)
	var same_sheet: String = _T.assert_eq(
		floor_item.tile_source_id, wall["source"], "floor shares the wall's sheet"
	)
	if same_sheet != "":
		return same_sheet

	return _T.assert_false(
		wall["rect"].has_point(floor_item.atlas_location),
		"stone floor %s must sit outside the wall rect %s" % [floor_item.atlas_location, wall["rect"]]
	)


## The floor goes on layer 2 and the wall on layer 1, same as the wood pair. A floor
## on layer 1 would occupy the cell walls and resources use.
func test_stone_set_uses_the_same_layers_as_the_wood_set() -> String:
	var layers := {
		Types.Item.StoneWall: items.get_item(Types.Item.WoodWall).layer,
		Types.Item.StoneFloor: items.get_item(Types.Item.WoodFloor).layer,
	}
	for type in STONE_SET:
		var item: GameItem = items.get_item(type)
		var layer: String = _T.assert_eq(item.layer, layers[type], "%s layer" % item.name)
		if layer != "":
			return layer

		var placeable: String = _T.assert_true(item.is_placeable, "%s is placeable" % item.name)
		if placeable != "":
			return placeable
	return ""


## Both are craftable at the sawmill, and both cost something the player can actually
## hold. A recipe naming an item that no station can produce and no node drops is the
## failure mode test_ore_chain guards for the ore tiers.
func test_stone_set_is_craftable_from_stone() -> String:
	for type in STONE_SET:
		var recipe = recipes.get_sawmill_recipe(type)
		var exists: String = _T.assert_true(recipe != null, "sawmill recipe for %d" % type)
		if exists != "":
			return exists

		var costs: Dictionary = recipe.cost_list
		var priced: String = _T.assert_gt(costs.size(), 0, "%d has ingredients" % type)
		if priced != "":
			return priced

		for ingredient in costs:
			var known: String = _T.assert_true(
				items.get_item(ingredient) != null, "ingredient %d is a real item" % ingredient
			)
			if known != "":
				return known

			var amount: String = _T.assert_gt(costs[ingredient], 0, "cost of %d" % ingredient)
			if amount != "":
				return amount
	return ""


## Neither is available on a clean save - they are a skill purchase, and the skill
## that grants them has to name products the sawmill list actually contains, or
## Recipes.add_recipe pushes a warning and unlocks nothing.
func test_a_skill_unlocks_the_stone_set() -> String:
	var tree := SkillTree.new()
	var granted := {}

	for id in tree.order:
		for unlock in tree.get_skill(id).recipes:
			if unlock["product"] in STONE_SET:
				granted[unlock["product"]] = unlock["station"]

	for type in STONE_SET:
		var unlocked: String = _T.assert_true(granted.has(type), "a skill unlocks %d" % type)
		if unlocked != "":
			return unlocked

		var station: String = _T.assert_eq(
			granted[type], Types.Item.Sawmill, "%d unlocks at the sawmill" % type
		)
		if station != "":
			return station

	for entry in recipes.DAY_ONE_RECIPES:
		var locked: String = _T.assert_false(
			entry["product"] in STONE_SET, "%s is not a day-one recipe" % entry["product"]
		)
		if locked != "":
			return locked
	return ""
