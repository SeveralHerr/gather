extends RefCounted

## The decorative grass tufts (gather-5z0).
##
## Two halves, and the second is the one that matters. `decor_at` is a pure function and
## easy to assert; the property worth protecting is that the tufts are INERT — that a layer
## nothing enumerates cannot make a cell refuse a resource, a building or a spawn. That is
## a claim about is_occupied(), so it needs the real tileset and a real TileMap.

const TILE_MAP_SCENE := "res://world/tile_map.tscn"

var items: Items
var resources: Resources
var tile_map: TileMap
var handler: TileMapHandler


func setup() -> void:
	# Autoloads are unavailable under the headless --script runner, so the registries are
	# built directly, the way test_wall_placement does it.
	items = Items.new()
	items._ready()

	resources = Resources.new()
	resources.items = items
	resources._ready()

	# The real tileset: the tufts are a source id in it, and a hand-built stand-in would be
	# asserting against a source of its own invention.
	tile_map = load(TILE_MAP_SCENE).instantiate()

	# tile_map.tscn declares only Ground and Resources; everything above that is added by
	# main.tscn's instance override, so a standalone instance is short of the decor layer
	# and every write to it would error out. A runtime error inside a `-> String` test still
	# returns "" and counts as a pass (gather-1t9), so this has to be right or the file
	# below goes green while asserting nothing.
	while tile_map.get_layers_count() <= TileMapHandler.DECOR_LAYER:
		tile_map.add_layer(-1)

	handler = TileMapHandler.new()
	handler.tileMap = tile_map
	handler.resources = resources
	handler.items = items


func teardown() -> void:
	for node in [handler, tile_map, resources, items]:
		if node != null:
			node.free()
	handler = null
	tile_map = null
	resources = null
	items = null


## Paints `cells` as plain grass on the ground layer, bypassing the terrain solver so the
## test controls exactly which cells are grass and which are coastline.
func _paint_grass(cells: Array) -> void:
	for cell in cells:
		tile_map.set_cell(0, cell, 4, TileMapHandler.GRASS_ATLAS)


func _decor_cells() -> Array:
	return tile_map.get_used_cells(TileMapHandler.DECOR_LAYER)


# --- the scatter itself ------------------------------------------------------


## The whole no-save-format-change argument rests on this: the same cell and seed must give
## the same answer on a later run, or a load would repaint a different island.
func test_decor_is_deterministic_in_cell_and_seed() -> String:
	for x in range(-20, 20):
		for y in range(-20, 20):
			var cell := Vector2i(x, y)
			var first := TileMapHandler.decor_at(cell, 12345)
			var second := TileMapHandler.decor_at(cell, 12345)
			if first != second:
				return "decor_at(%s, 12345) returned %d then %d" % [cell, first, second]
	return ""


func test_a_different_seed_scatters_differently() -> String:
	var differences := 0
	for x in range(-20, 20):
		for y in range(-20, 20):
			var cell := Vector2i(x, y)
			if TileMapHandler.decor_at(cell, 1) != TileMapHandler.decor_at(cell, 2):
				differences += 1

	# 1600 cells. Two seeds agreeing everywhere would mean the seed is not reaching the hash
	# at all — which is exactly what a plain `hash(cell)` would have done.
	if differences < 100:
		return "seeds 1 and 2 differ on only %d of 1600 cells" % [differences]
	return ""


## Density, checked over enough cells that a weak hash cannot hide inside the tolerance.
## The bound is deliberately loose — this is asserting that DECOR_CHANCE is honoured at all,
## not that the generator is cryptographic.
func test_density_is_near_the_configured_chance() -> String:
	var total := 0
	var tufts := 0
	for x in range(-60, 60):
		for y in range(-60, 60):
			total += 1
			if TileMapHandler.decor_at(Vector2i(x, y), 99) >= 0:
				tufts += 1

	var observed := float(tufts) / float(total)
	if absf(observed - TileMapHandler.DECOR_CHANCE) > 0.04:
		return "density %.3f is not within 0.04 of DECOR_CHANCE %.3f (%d of %d cells)" % [
			observed, TileMapHandler.DECOR_CHANCE, tufts, total
		]
	return ""


## Both orientations have to be reachable, or the flip is dead code and every clump on the
## island leans the same way.
func test_both_orientations_are_produced() -> String:
	var upright := 0
	var flipped := 0
	for x in range(-40, 40):
		for y in range(-40, 40):
			var cell := Vector2i(x, y)
			if TileMapHandler.decor_at(cell, 7) < 0:
				continue
			if TileMapHandler.decor_flip(cell, 7) == TileSetAtlasSource.TRANSFORM_FLIP_H:
				flipped += 1
			else:
				upright += 1

	if upright == 0 or flipped == 0:
		return "expected both orientations, got %d upright and %d flipped" % [upright, flipped]
	return ""


## Every variant on the sheet has to be reachable. A weight table is exactly the kind of
## thing that ships with a typo putting one entry permanently out of range, and the symptom
## — a flower nobody ever sees — is invisible in any single playthrough.
func test_every_variant_is_reachable() -> String:
	var seen := {}
	for x in range(-70, 70):
		for y in range(-70, 70):
			var variant := TileMapHandler.decor_at(Vector2i(x, y), 3)
			if variant >= 0:
				seen[variant] = seen.get(variant, 0) + 1

	for i in TileMapHandler.DECOR_WEIGHTS.size():
		if not seen.has(i):
			return "variant %d (atlas %s) never came up in 19600 cells" % [
				i, TileMapHandler.decor_atlas(i)
			]

	# Never out of range, or set_cell would be handed an atlas coordinate off the sheet.
	for variant in seen:
		if variant >= TileMapHandler.DECOR_WEIGHTS.size():
			return "decor_at returned %d, past the end of DECOR_WEIGHTS" % [variant]
	return ""


## The weights have to actually order the variants, or they are decoration on decoration.
## Grass must beat flowers; a map where every other tile is a poppy is a different game.
func test_grass_outnumbers_flowers() -> String:
	var grass := 0
	var flowers := 0
	for x in range(-70, 70):
		for y in range(-70, 70):
			var variant := TileMapHandler.decor_at(Vector2i(x, y), 11)
			if variant < 0:
				continue
			# The first three columns of the sheet are grass clumps, the last three flowers.
			if variant < 3:
				grass += 1
			else:
				flowers += 1

	if flowers == 0:
		return "no flowers at all in 19600 cells"
	if grass < flowers * 2:
		return "expected grass to outnumber flowers 2:1 at least, got %d grass to %d flowers" % [
			grass, flowers
		]
	return ""


# --- what it paints ----------------------------------------------------------


## The headline requirement: tufts on plain grass, never on the coastline variants the
## terrain solver produces around the island's edge.
func test_only_plain_grass_gets_a_tuft() -> String:
	var grass: Array = []
	for x in range(-10, 10):
		for y in range(-10, 10):
			grass.append(Vector2i(x, y))
	_paint_grass(grass)

	# A ring of coastline just outside it. (0, 15) is the coastline stand-in test_wall_placement
	# already uses — a real ground tile on source 4 that is not GRASS_ATLAS.
	var edges: Array = []
	for x in range(-11, 11):
		for cell in [Vector2i(x, -11), Vector2i(x, 10)]:
			edges.append(cell)
			tile_map.set_cell(0, cell, 4, Vector2i(0, 15))

	handler.refresh_grass_decor()

	for cell in edges:
		if tile_map.get_cell_source_id(TileMapHandler.DECOR_LAYER, cell) != -1:
			return "coastline cell %s was given a tuft" % [cell]

	if _decor_cells().is_empty():
		return "no tufts were painted at all, so the coastline check proves nothing"
	return ""


## Repainting must not accumulate. refresh_grass_decor is called from four places and two of
## them can fire on the same purchase, so a non-idempotent repaint would double-write.
func test_repainting_is_idempotent() -> String:
	_paint_grass(TileMapHandler.cells_within(8))

	handler.refresh_grass_decor()
	var first := _decor_cells()
	first.sort()

	handler.refresh_grass_decor()
	var second := _decor_cells()
	second.sort()

	if first != second:
		return "repaint changed the tufts: %d cells then %d" % [first.size(), second.size()]
	return ""


## Land that stops being grass loses its tufts. This is what a total repaint buys over an
## incremental one, and the reverse case — coastline becoming grass when a parcel is bought
## — is the same code path.
func test_a_cell_that_stops_being_grass_loses_its_tuft() -> String:
	_paint_grass(TileMapHandler.cells_within(8))
	handler.refresh_grass_decor()

	var tufted = null
	for cell in _decor_cells():
		tufted = cell
		break
	if tufted == null:
		return "no tuft was painted, so there is nothing to remove"

	tile_map.set_cell(0, tufted, 4, Vector2i(0, 15))
	handler.refresh_grass_decor()

	if tile_map.get_cell_source_id(TileMapHandler.DECOR_LAYER, tufted) != -1:
		return "cell %s kept its tuft after ceasing to be plain grass" % [tufted]
	return ""


# --- decoration never shares a cell ------------------------------------------


## Nothing is decorated under a resource. The scatter is deliberately blind to what is
## standing on a cell — it is a pure function of the coordinate — so this is entirely the
## occupancy check's doing, and removing that check is a one-line edit that no other test in
## this file would notice.
func test_no_decor_under_a_resource() -> String:
	var cells := TileMapHandler.cells_within(8)
	_paint_grass(cells)
	handler.refresh_grass_decor()

	var bare := _decor_cells()
	if bare.is_empty():
		return "nothing was decorated, so covering it proves nothing"

	# A tree on every decorated cell.
	var tree: GameResource = resources.Get(Types.Item.Tree)
	for cell in bare:
		tile_map.set_cell(1, cell, tree.tile_source_id, tree.atlas_location)

	handler.refresh_grass_decor()

	for cell in bare:
		if tile_map.get_cell_source_id(TileMapHandler.DECOR_LAYER, cell) != -1:
			return "cell %s kept its decoration under a tree" % [cell]
	return ""


## Placing something clears that one cell without a full repaint — the path the game
## actually takes, since set_tile is what every placement goes through.
func test_placing_a_tile_clears_the_decoration_under_it() -> String:
	_paint_grass(TileMapHandler.cells_within(8))
	handler.refresh_grass_decor()

	var target = null
	for cell in _decor_cells():
		target = cell
		break
	if target == null:
		return "nothing was decorated, so there is nothing to cover"

	var tree: GameResource = resources.Get(Types.Item.Tree)
	handler.set_tile(target, tree.tile_source_id, tree.atlas_location, tree.layer, tree.is_scene_tile)

	if tile_map.get_cell_source_id(TileMapHandler.DECOR_LAYER, target) != -1:
		return "decoration survived a tile being placed on %s" % [target]
	return ""


## And clearing the cell puts it back — the SAME one, because the scatter is a function of
## the coordinate. A chopped forest that came back covered in new flowers would read as the
## world reseeding itself every time the player gathered.
func test_clearing_a_tile_restores_the_same_decoration() -> String:
	_paint_grass(TileMapHandler.cells_within(8))
	handler.refresh_grass_decor()

	var target = null
	for cell in _decor_cells():
		target = cell
		break
	if target == null:
		return "nothing was decorated, so there is nothing to restore"

	var before := tile_map.get_cell_atlas_coords(TileMapHandler.DECOR_LAYER, target)
	var before_alt := tile_map.get_cell_alternative_tile(TileMapHandler.DECOR_LAYER, target)

	var tree: GameResource = resources.Get(Types.Item.Tree)
	handler.set_tile(target, tree.tile_source_id, tree.atlas_location, tree.layer, tree.is_scene_tile)
	handler.clear_tile(target)

	if tile_map.get_cell_source_id(TileMapHandler.DECOR_LAYER, target) == -1:
		return "decoration did not come back after %s was cleared" % [target]
	if tile_map.get_cell_atlas_coords(TileMapHandler.DECOR_LAYER, target) != before:
		return "cell %s came back as a different variant (%s, was %s)" % [
			target, tile_map.get_cell_atlas_coords(TileMapHandler.DECOR_LAYER, target), before
		]
	if tile_map.get_cell_alternative_tile(TileMapHandler.DECOR_LAYER, target) != before_alt:
		return "cell %s came back mirrored differently" % [target]
	return ""


## A floor counts too, not just a resource. Floors are on layer 2 and are the one thing
## is_occupied treats differently, so they are exactly where a hand-rolled occupancy check
## would have diverged from the game's own.
func test_a_floor_clears_the_decoration_under_it() -> String:
	_paint_grass(TileMapHandler.cells_within(8))
	handler.refresh_grass_decor()

	var target = null
	for cell in _decor_cells():
		target = cell
		break
	if target == null:
		return "nothing was decorated, so there is nothing to cover"

	var floor_item: GameItem = items.get_item(Types.Item.WoodFloor)
	if floor_item == null:
		return "no WoodFloor registered, so this asserts nothing"

	# Written straight to the layer rather than through set_tile, deliberately. set_tile
	# calls play_audio, and WoodFloor is one of the types that reaches for `sound_manager` —
	# which this handler has none of, so the call would raise, abort the method, and return
	# "" for a pass (gather-1t9). The set_tile hook itself is covered by the resource test
	# above; what this one is for is the layer-2 half of the occupancy rule.
	tile_map.set_cell(floor_item.layer, target, floor_item.tile_source_id, floor_item.atlas_location)
	handler.refresh_decor_cell(target)

	if tile_map.get_cell_source_id(TileMapHandler.DECOR_LAYER, target) != -1:
		return "decoration survived a floor laid on %s" % [target]
	return ""


# --- and that it changes nothing ---------------------------------------------


## The requirement in the user's own terms: a tuft must not stop a resource spawning.
##
## Asserted as a transition rather than as a state — is_occupied is read before and after
## the repaint and must not move on any cell. A bare "is_occupied() == false" would pass
## just as happily if refresh_grass_decor had painted nothing at all.
func test_tufts_do_not_occupy_their_cell() -> String:
	var cells := TileMapHandler.cells_within(8)
	_paint_grass(cells)

	var before := {}
	for cell in cells:
		before[cell] = [handler.is_occupied(cell), handler.is_occupied(cell, true)]

	handler.refresh_grass_decor()

	if _decor_cells().is_empty():
		return "no tufts were painted, so this asserts nothing"

	for cell in cells:
		var after := [handler.is_occupied(cell), handler.is_occupied(cell, true)]
		if after != before[cell]:
			return "is_occupied(%s) went from %s to %s once it had a tuft" % [
				cell, before[cell], after
			]
	return ""


## The other half of the same guarantee: the tuft layer must not leak into the land census
## either, or every ceiling scaled against count_land_tiles() would move.
func test_tufts_do_not_change_the_land_count() -> String:
	_paint_grass(TileMapHandler.cells_within(8))

	var before := handler.count_land_tiles()
	handler.refresh_grass_decor()
	var after := handler.count_land_tiles()

	if before != after:
		return "count_land_tiles went from %d to %d" % [before, after]
	if before == 0:
		return "no land was painted, so the count proves nothing"
	return ""


## Decoration is not terrain: no variant may carry a collision polygon or belong to a terrain
## set, or the island would sprout invisible walls wherever one landed and the terrain solver
## would start rewriting them. Checked for every variant, because the sheet is edited by
## adding a column and it is the newest column that will be the one missing an entry.
func test_no_variant_has_collision_or_terrain() -> String:
	var source := tile_map.tile_set.get_source(TileMapHandler.DECOR_SOURCE_ID) as TileSetAtlasSource
	if source == null:
		return "source %d is not an atlas source in the tileset" % [TileMapHandler.DECOR_SOURCE_ID]

	for variant in TileMapHandler.DECOR_WEIGHTS.size():
		var atlas := TileMapHandler.decor_atlas(variant)
		var data := source.get_tile_data(atlas, 0)
		if data == null:
			return "the tileset has no tile at %s on source %d" % [
				atlas, TileMapHandler.DECOR_SOURCE_ID
			]

		for physics_layer in tile_map.tile_set.get_physics_layers_count():
			if data.get_collision_polygons_count(physics_layer) != 0:
				return "variant %s carries a collision polygon on physics layer %d" % [
					atlas, physics_layer
				]

		if data.terrain_set != -1:
			return "variant %s belongs to terrain set %d and would be pulled into the solver" % [
				atlas, data.terrain_set
			]
	return ""


## The sheet and the table have to agree on how many tiles there are. They are edited in
## different files, and the failure is silent in exactly one direction: a variant weighted in
## main.gd but absent from the atlas paints nothing at all.
func test_every_variant_exists_on_the_sheet() -> String:
	var source := tile_map.tile_set.get_source(TileMapHandler.DECOR_SOURCE_ID) as TileSetAtlasSource
	if source == null:
		return "source %d is not an atlas source in the tileset" % [TileMapHandler.DECOR_SOURCE_ID]

	if source.get_tiles_count() != TileMapHandler.DECOR_WEIGHTS.size():
		return "the decor sheet has %d tiles but DECOR_WEIGHTS lists %d" % [
			source.get_tiles_count(), TileMapHandler.DECOR_WEIGHTS.size()
		]
	return ""
