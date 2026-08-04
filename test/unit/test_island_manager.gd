extends RefCounted

## Placement tests for the pregenerated islands.
##
## The feature's whole promise is that buying land eventually walks you to every island,
## and whether that holds is decided by a noise field rather than by any line of code - so
## it is a property of the seed and cannot be settled by reading the diff, or by launching
## the game once and liking what you see. One run is one seed.
##
## These build the home island's final coastline exactly as main.gd does, place the
## islands against it, and flood-fill to check they are actually joined. Over many seeds,
## headlessly, because a one-in-twenty stranding is invisible in a single run and would
## reach a player as a progression that silently dead-ends.

const SEEDS_TO_TRY := 200

var _T

var manager: IslandManager


func setup() -> void:
	manager = IslandManager.new()


func teardown() -> void:
	if manager:
		manager.free()
		manager = null


## The home island at maximum size, cut the way main.gd cuts it: PERLIN, the same
## threshold and scale, and the radius LandManager tops out at.
func _home_land(seed_value: int) -> Dictionary:
	var field := FastNoiseLite.new()
	field.set_noise_type(FastNoiseLite.TYPE_PERLIN)
	field.set_seed(seed_value)

	var max_radius := LandManager.radius_for(LandManager.MAX_PARCELS)
	var lookup := {}
	for x in range(-max_radius, max_radius + 1):
		for y in range(-max_radius, max_radius + 1):
			if Vector2(x, y).length() > max_radius:
				continue
			if field.get_noise_2d(x, y) < 0.0:
				lookup[Vector2i(x, y)] = true
	return lookup


## One seed's finished world, built the way IslandManager.generate() builds it - including
## which anchor set each step is judged against, because that distinction is the bug this
## file exists to catch. Returns {world: Dictionary, cells: {id: Array}}.
func _world_for_seed(seed_value: int) -> Dictionary:
	manager.islands_seed = seed_value

	var home := _home_land(seed_value)
	var anchor := IslandManager.main_body(home)
	var walkable_anchor := IslandManager.walkable_body(anchor)
	var world := home.duplicate()
	var taken := []
	var cells_by_id := {}

	for definition in IslandManager.placement_order():
		var angle: float = manager._choose_angle(definition["distance"], taken, walkable_anchor)
		taken.append(angle)
		var centre: Vector2i = IslandManager._cell_along(angle, definition["distance"])
		var cells := IslandManager.island_cells(centre, definition["radius"], seed_value, definition["id"])
		var all: Array = []
		for cell in cells:
			world[cell] = true
			all.append(cell)
		for cell in manager._isthmus_cells(centre, definition["radius"], angle, anchor, cells):
			world[cell] = true
			all.append(cell)
		cells_by_id[definition["id"]] = {"centre": centre, "cells": all}

	return {"world": world, "cells": cells_by_id}


## The one that matters. A stranded island is a dead end the player can see and never
## reach, with nothing logged anywhere.
##
## Judged with IslandManager.walkable_body - the SAME predicate refresh_connections opens an
## island with - and that is the entire point of the test rather than an implementation
## detail. This swept 200 seeds green for months while real playthroughs dead-ended, because
## it flooded raw land: raw land is optimistic by a coastline ring in every direction, so it
## agreed with the placement code's own optimistic answer instead of checking it. 39 of these
## 600 island-seed pairs were unreachable in the running game at the time (gather-37z).
func test_every_island_connects_to_home_across_many_seeds() -> String:
	var stranded := []

	for i in SEEDS_TO_TRY:
		var seed_value := 1000 + i * 7919
		var built := _world_for_seed(seed_value)
		var reachable := IslandManager.walkable_body(built["world"])

		for id in built["cells"]:
			# Any cell, not the centre: that is the question refresh_connections asks.
			var joined := false
			for cell in built["cells"][id]["cells"]:
				if reachable.has(cell):
					joined = true
					break
			if not joined:
				stranded.append("seed %d: %s at %s" % [seed_value, id, built["cells"][id]["centre"]])

	return _T.assert_eq(stranded.size(), 0, "stranded islands: %s" % [stranded.slice(0, 5)])


## An island has to be solid where its contents go. The home island's own generator cannot
## promise this - it thresholds the field and can return an empty or near-empty set - which
## is exactly why island_cells decides by distance and only lets the noise ruffle the edge.
func test_island_centre_is_always_land() -> String:
	for i in SEEDS_TO_TRY:
		var seed_value := 500 + i * 104729
		for definition in IslandManager.placement_order():
			var cells := IslandManager.island_cells(Vector2i(40, 40), definition["radius"], seed_value, definition["id"])
			if not cells.has(Vector2i(40, 40)):
				return "seed %d: %s has no land at its own centre" % [seed_value, definition["id"]]
			var too_small: String = _T.assert_gt(cells.size(), 10, "%s at seed %d is a sliver" % [definition["id"], seed_value])
			if too_small != "":
				return too_small
	return ""


## Islands must not overlap each other, or two themed spawn tables fight over the same
## cells and whichever registered first silently wins.
func test_islands_do_not_overlap() -> String:
	for i in SEEDS_TO_TRY:
		var seed_value := 31 + i * 6151
		manager.islands_seed = seed_value

		var anchor := IslandManager.walkable_body(IslandManager.main_body(_home_land(seed_value)))
		var taken := []
		var claimed := {}

		for definition in IslandManager.placement_order():
			var angle: float = manager._choose_angle(definition["distance"], taken, anchor)
			taken.append(angle)
			var centre: Vector2i = IslandManager._cell_along(angle, definition["distance"])
			for cell in IslandManager.island_cells(centre, definition["radius"], seed_value, definition["id"]):
				if claimed.has(cell):
					return "seed %d: %s overlaps %s at %s" % [seed_value, definition["id"], claimed[cell], cell]
				claimed[cell] = definition["id"]
	return ""


## The seeded iron and gold on the ore island, checked the same way and for the same reason
## as the placement above: island_cells ruffles the coastline per seed, so "the veins landed
## on land" is a property of the seed. A vein written onto a bitten-away or coastline cell is
## not a vein the player mines - is_occupied refuses the write outright - and it would fail
## on some fraction of worlds while looking perfect in the one anybody launched.
func test_ore_island_veins_land_on_solid_ground_across_many_seeds() -> String:
	var definition := IslandManager._definition_for(IslandManager.SEEDED_VEIN_ISLAND)
	var wanted := IslandManager.seeded_vein_total()
	var furthest_ring: int = 0
	for ring in IslandManager.VEIN_RING_RADII:
		furthest_ring = maxi(furthest_ring, int(ring))

	for i in SEEDS_TO_TRY:
		var seed_value := 4001 + i * 49999
		# A different centre every seed, on the ring the ore island actually sits on - the
		# noise is sampled in absolute coordinates, so the island's shape depends on where
		# it is as much as on the seed.
		var centre := IslandManager._cell_along(TAU * float(i) / float(SEEDS_TO_TRY), definition["distance"])

		var cells := IslandManager.vein_cells(
			centre, definition["radius"], seed_value, IslandManager.SEEDED_VEIN_ISLAND, wanted
		)

		var count: String = _T.assert_eq(cells.size(), wanted, "seed %d: ore island got %d veins" % [seed_value, cells.size()])
		if count != "":
			return count

		var land := {}
		for cell in IslandManager.island_cells(centre, definition["radius"], seed_value, IslandManager.SEEDED_VEIN_ISLAND):
			land[cell] = true

		var seen := {}
		for cell in cells:
			if seen.has(cell):
				return "seed %d: two veins share cell %s" % [seed_value, cell]
			seen[cell] = true

			if not land.has(cell):
				return "seed %d: vein at %s is not on the ore island" % [seed_value, cell]

			# Stricter than "is land": a cell with a water neighbour solves to coastline
			# rather than grass, and nothing can be placed on coastline.
			if not IslandManager._is_interior(cell, land):
				return "seed %d: vein at %s is on the coastline" % [seed_value, cell]

			# Well inside the disc, which is also what keeps them off the isthmus - that
			# trails away from the island entirely. Measured per axis rather than as a
			# length: a ring cell is cos/sin rounded to the grid, so the furthest ring puts
			# a vein at (2, 3), which is 3.6 tiles away and perfectly correct.
			var offset := cell - centre
			if maxi(absi(offset.x), absi(offset.y)) > furthest_ring:
				return "seed %d: vein at %s is %s off centre, past the %d-tile ring" % [seed_value, cell, offset, furthest_ring]

	return ""


## Why the veins are seeded at all. If iron or gold ever joins the starting unlocked set,
## the spawn roll places them on the ore island by itself and this whole mechanism is
## redundant - worse, it stacks a fixed handful on top of a roll that is already producing
## them. That is a balance decision, so it should fail here and be made deliberately.
func test_seeded_veins_are_the_types_the_spawn_roll_cannot_place() -> String:
	var weights: Dictionary = IslandManager._definition_for(IslandManager.SEEDED_VEIN_ISLAND)["weights"]

	for entry in IslandManager.SEEDED_VEINS:
		var type = entry["type"]
		if ResourceManager2.STARTING_RESOURCES.has(type):
			return "%s is unlocked from the start, so the ore island already rolls it - drop it from SEEDED_VEINS" % type
		var weight: float = weights.get(type, 0.0)
		var rollable: String = _T.assert_gt(weight, 0.0, "%s is seeded but the ore island's weights would never grow it back once unlocked" % type)
		if rollable != "":
			return rollable

	return ""


## A few means a few. The veins are a teaser for crossing the water; the skills are still
## what make iron and gold renewable. Sized against what they buy: 5 IronBar for an iron
## pickaxe, 12 coins for the first parcel of land.
func test_seeded_veins_stay_a_handful() -> String:
	var seeded := {}
	for entry in IslandManager.SEEDED_VEINS:
		seeded[entry["type"]] = int(entry["count"])

	var has_iron: String = _T.assert_true(seeded.get(Types.Item.IronResource, 0) > 0, "no iron seeded on the ore island")
	if has_iron != "":
		return has_iron

	var has_gold: String = _T.assert_true(seeded.get(Types.Item.GoldResource, 0) > 0, "no gold seeded on the ore island")
	if has_gold != "":
		return has_gold

	# Five bars make an iron pickaxe and ore smelts 1:1, so a fifth vein hands the tier over
	# rather than teasing it.
	var iron: String = _T.assert_true(seeded[Types.Item.IronResource] <= 4, "seeded iron is a supply line, not a teaser")
	if iron != "":
		return iron

	# Gold smelts 1:1 into coins and the first parcel costs LandManager.BASE_COST.
	var gold: int = seeded[Types.Item.GoldResource]
	return _T.assert_true(
		gold * 2 < LandManager.BASE_COST,
		"seeded gold (%d nodes) is a meaningful share of a parcel at %d coins" % [gold, LandManager.BASE_COST]
	)


## A reward owed but not yet on the ground has to survive a save.
##
## The chest spends about a second in the air, and for that second nothing else in the world
## holds the reward: the boss is flagged dead so it is never placed again, and no chest tile
## exists yet for the tile save to write down. A save landing in that window is the entire
## failure case, which is exactly why it needs a test - it is a one-in-a-thousand timing that
## costs the player the whole payout for the hardest fight in the game, and it fails the
## quiet way, with a load that succeeds and simply hands back less.
func test_pending_reward_survives_a_save_taken_mid_drop() -> String:
	manager.pending_rewards[IslandManager.BOSS_ID] = true
	manager.bosses_defeated[IslandManager.BOSS_ID] = true

	var saved := manager.saveObject()

	var reloaded := IslandManager.new()
	reloaded.loadObject(saved)
	var pending: bool = reloaded.pending_rewards.get(IslandManager.BOSS_ID, false)
	var defeated := reloaded.is_boss_defeated(IslandManager.BOSS_ID)
	reloaded.free()

	var owed: String = _T.assert_true(pending, "a chest still in the air was not owed after a reload")
	if owed != "":
		return owed
	return _T.assert_true(defeated, "the boss came back alive alongside its unpaid reward")


## The other half: a chest that already landed must NOT come back owed, or every load hands
## out a second one.
func test_a_landed_reward_is_not_owed_again() -> String:
	manager.bosses_defeated[IslandManager.BOSS_ID] = true

	var reloaded := IslandManager.new()
	reloaded.loadObject(manager.saveObject())
	var pending: bool = reloaded.pending_rewards.get(IslandManager.BOSS_ID, false)
	reloaded.free()

	return _T.assert_false(pending, "a reward that was already collected came back owed")


## The arena's payout is the last one in the game and is spent on the last two parcels of
## land, so it is priced against that curve rather than picked. Guarded here because it is a
## bare number in a table: it reads as fine at any value, and the version that shipped for
## months was 40 coins - 1.6% of the next thing the player wanted, which is a rounding error
## handed over for killing the boss.
func test_boss_coins_are_worth_the_fight() -> String:
	var coins := 0
	for entry in IslandManager.BOSS_REWARD:
		if entry["type"] == Types.Item.Coin:
			coins = int(entry["count"])

	# The twelfth parcel, i.e. the most expensive single thing the player ever buys.
	var last_parcel := LandManager.cost_for_parcel(LandManager.MAX_PARCELS - 1, 1.0)

	var meaningful: String = _T.assert_gte(
		float(coins),
		float(last_parcel) * 0.15,
		"%d coins is noise next to the %d-coin parcel the player is saving for" % [coins, last_parcel]
	)
	if meaningful != "":
		return meaningful

	# And not the parcel itself. The boss is a milestone on the way to maxing the island,
	# not a way to skip the end of the land economy.
	return _T.assert_true(
		float(coins) < float(last_parcel) * 0.6,
		"%d coins buys most of the %d-coin final parcel outright" % [coins, last_parcel]
	)


## Every island has to sit inside the reach of a fully bought home island, or no amount of
## land purchasing brings it into range.
func test_islands_sit_within_max_home_reach() -> String:
	var max_radius := LandManager.radius_for(LandManager.MAX_PARCELS)
	for definition in IslandManager.placement_order():
		var nearest_edge: int = definition["distance"] - definition["radius"]
		var check: String = _T.assert_true(
			nearest_edge <= max_radius,
			"%s's near edge is %d tiles out but home tops out at %d" % [definition["id"], nearest_edge, max_radius]
		)
		if check != "":
			return check
	return ""
