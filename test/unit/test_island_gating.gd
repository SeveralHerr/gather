extends RefCounted

## An island is scenery until the home coastline reaches it.
##
## Nothing is placed on one, nothing wanders onto it, and its grass does not count toward
## anybody's ceiling until the player can walk there. The failure this guards against is not
## a crash - it is a fully stocked ore island sitting across the water for the whole early
## game, which looks entirely correct in a screenshot and is only wrong in relation to a
## coastline the screenshot does not show.
##
## The gate is one bool travelling through four systems, and the interesting cases are the
## ones where it has to survive a trip: rebuilding an island's region on load, and a save
## written before the gate existed.

var _T

var manager: IslandManager


func setup() -> void:
	manager = IslandManager.new()


func teardown() -> void:
	if manager:
		manager.free()
		manager = null


func _region(id: String, cells: Array) -> LandRegion:
	var region := LandRegion.new()
	region.id = id
	region.set_cells(cells)
	return region


## Home is not an island and never waits for anything, so the default has to be open. A
## default of closed would silently stop the mainland's own respawn timer.
func test_a_plain_region_is_open_by_default() -> String:
	var region := LandRegion.new()

	var err: String = _T.assert_true(region.connected, "a region nobody gated is open")
	if err != "":
		return err

	err = _T.assert_true(region.accepts_ambient_resources(), "an open region takes ambient resources")
	if err != "":
		return err

	return _T.assert_true(region.accepts_ambient_enemies(), "an open region takes ambient enemies")


## The two halves are separate on purpose: the boss arena refuses ambient spawning forever,
## while the grove has merely not been reached yet. Collapsing them into one flag would make
## opening the arena start restocking it.
func test_being_reachable_does_not_override_opting_out() -> String:
	var arena := LandRegion.new()
	arena.ambient_resources = false
	arena.ambient_enemies = false
	arena.connected = true

	var err: String = _T.assert_false(arena.accepts_ambient_resources(), "a reached arena still grows nothing")
	if err != "":
		return err

	return _T.assert_false(arena.accepts_ambient_enemies(), "a reached arena still gets no wanderers")


## And the other direction: an island that wants resources still gets none while closed.
func test_wanting_resources_does_not_override_being_closed() -> String:
	var grove := LandRegion.new()
	grove.ambient_resources = true
	grove.ambient_enemies = true
	grove.connected = false

	var err: String = _T.assert_false(grove.accepts_ambient_resources(), "an unreached grove grows nothing")
	if err != "":
		return err

	return _T.assert_false(grove.accepts_ambient_enemies(), "an unreached grove gets no wanderers")


## One cell is enough. An island's interior is a single connected patch of grass, so
## reaching any of it is reaching the island - and requiring more would leave an island the
## player is standing on closed because its far side is still coastline.
func test_one_reachable_cell_opens_an_island() -> String:
	var region := _region("forest", [Vector2i(20, 0), Vector2i(21, 0), Vector2i(20, 1)])

	var err: String = _T.assert_true(
		IslandManager._region_is_walkable(region, {Vector2i(20, 1): true}),
		"a single cell in the flood opens the island"
	)
	if err != "":
		return err

	return _T.assert_false(
		IslandManager._region_is_walkable(region, {Vector2i(0, 0): true, Vector2i(1, 0): true}),
		"a flood that never reaches the island leaves it closed"
	)


## The isthmus counts. It is drawn at generation and trails well outside the island's own
## radius, so it is the first thing the growing coastline touches - judging membership by
## distance from the centre instead would leave the island closed for the several parcels
## during which the player can already walk onto the spit.
func test_the_isthmus_counts_as_reaching_the_island() -> String:
	var region := _region("forest", [Vector2i(20, 0), Vector2i(21, 0), Vector2i(14, 0), Vector2i(15, 0)])

	return _T.assert_true(
		IslandManager._region_is_walkable(region, {Vector2i(14, 0): true}),
		"reaching the spit opens the island it grew from"
	)


## An island that has been opened must stay open across a save. Re-deriving it would be
## harmless if opening were free, but opening is what stocks - so a re-open on every load
## tops an island the player has half cleared straight back up.
func test_an_open_island_survives_a_save_roundtrip() -> String:
	manager.islands = {
		"forest": {"centre": Vector2i(20, 0), "radius": 6, "angle": 0.0, "region": null, "connected": true},
		"ore": {"centre": Vector2i(0, 27), "radius": 6, "angle": 1.57, "region": null, "connected": false},
	}

	var payload := manager.saveObject()
	var restored := IslandManager.new()
	restored.loadObject(payload)
	var forest_open: bool = restored.islands["forest"]["connected"]
	var ore_open: bool = restored.islands["ore"]["connected"]
	restored.free()

	var err: String = _T.assert_true(forest_open, "the opened island comes back open")
	if err != "":
		return err

	return _T.assert_false(ore_open, "the island still across the water comes back closed")


## A save written before the gate existed carries no `connected` at all. It has to come back
## closed rather than defaulting open, because "open" is a claim about a coastline nobody has
## checked - reassert_after_load's flood fill is what re-opens whichever the player had in
## fact already reached.
func test_a_save_written_before_the_gate_comes_back_closed() -> String:
	var legacy := {
		"islands_seed": 12345,
		"boss_defeated": false,
		"ore_veins_seeded": true,
		"islands": [JSON.stringify({"id": "forest", "x": 20, "y": 0, "radius": 6, "angle": 0.0})],
	}

	manager.loadObject(legacy)

	var err: String = _T.assert_true(manager.islands.has("forest"), "the legacy island still loads")
	if err != "":
		return err

	return _T.assert_false(manager.islands["forest"]["connected"], "a legacy island comes back closed")


## Rebuilding an island's region is what a load does, and it builds a fresh LandRegion whose
## own default is open. The rebuild has to take the island's recorded state instead, or every
## load re-opens - and re-stocks - every island in the world.
func test_rebuilding_a_region_keeps_what_the_island_recorded() -> String:
	manager.islands = {
		"forest": {"centre": Vector2i(20, 0), "radius": 6, "angle": 0.0, "region": null, "connected": true},
		"ore": {"centre": Vector2i(0, 27), "radius": 6, "angle": 1.57, "region": null, "connected": false},
	}

	var err: String = _T.assert_true(manager._connected_state("forest"), "an opened island rebuilds open")
	if err != "":
		return err

	err = _T.assert_false(manager._connected_state("ore"), "a closed island rebuilds closed")
	if err != "":
		return err

	return _T.assert_false(manager._connected_state("boss"), "an island with no record at all rebuilds closed")


## The distances are what make the gate a progression rather than a formality: every island
## has to start beyond the coastline the player is given, or it is open on the first frame
## and none of the above ever runs.
func test_no_island_is_within_reach_of_the_starting_coastline() -> String:
	var start_radius := LandManager.radius_for(0)

	for definition in IslandManager.ISLANDS:
		var nearest_edge: int = int(definition["distance"]) - int(definition["radius"])
		var err: String = _T.assert_gt(
			float(nearest_edge),
			float(start_radius),
			"%s's near edge is %d tiles out and the starting coastline already reaches %d" % [
				definition["id"], nearest_edge, start_radius
			]
		)
		if err != "":
			return err

	return ""
