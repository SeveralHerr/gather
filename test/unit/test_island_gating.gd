extends RefCounted

## An island is a place from the first frame; it is only dangerous once you can walk there.
##
## `connected` gates enemies and the boss, and nothing else. Resources grow on a closed
## island - that is what makes the ore island across the water read as an ore island and
## worth saving up for, and a bare green disc promises nothing. The failure this guards
## against is not a crash: it is one of those two halves quietly acquiring the other's rule,
## which looks entirely correct in a screenshot and is wrong only in relation to a coastline
## the screenshot does not show.
##
## The gate is one bool travelling through several systems, and the interesting cases are the
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


## And the other direction, which is where the two halves part company: a grove nobody can
## reach yet still grows its trees, and still gets no wanderers.
##
## The resource half is the assertion that costs something to keep. It is one word away from
## the enemy half at every call site, and the version that gated both left every island a
## bare disc for the whole stretch the player spends looking at it and deciding whether to
## buy the land.
func test_a_closed_island_grows_resources_but_gets_no_enemies() -> String:
	var grove := LandRegion.new()
	grove.ambient_resources = true
	grove.ambient_enemies = true
	grove.connected = false

	var err: String = _T.assert_true(
		grove.accepts_ambient_resources(), "an unreached grove still grows its trees"
	)
	if err != "":
		return err

	return _T.assert_false(grove.accepts_ambient_enemies(), "an unreached grove gets no wanderers")


## Opening an island changes exactly one of the two answers. Stated as a transition rather
## than as two independent reads, because the bug shape here is a refactor that reunites the
## halves - and a pair of static assertions above would both still pass if `connected` were
## put back in front of the resource check, as long as somebody also updated them.
func test_opening_an_island_adds_enemies_and_nothing_else() -> String:
	var grove := LandRegion.new()
	grove.connected = false

	var resources_before := grove.accepts_ambient_resources()
	var enemies_before := grove.accepts_ambient_enemies()

	grove.connected = true

	var err: String = _T.assert_true(
		resources_before and grove.accepts_ambient_resources(),
		"resources were unaffected by the coastline arriving"
	)
	if err != "":
		return err

	err = _T.assert_false(enemies_before, "and enemies were held back before it did")
	if err != "":
		return err

	return _T.assert_true(grove.accepts_ambient_enemies(), "and are let in once it has")


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


# --- per-island boss state (gather-302) --------------------------------------


func test_a_pre_keyed_save_still_reports_its_boss_dead() -> String:
	# The migration, and the bug it prevents is the one the flag was added for: a save
	# written before the state became keyed carries only the scalar `boss_defeated`, and
	# reading it as false resurrects a boss the player has already killed on every load.
	var manager := IslandManager.new()
	manager.loadObject({
		"islands_seed": 1,
		"boss_defeated": true,
		"islands": [],
	})
	var defeated: bool = manager.is_boss_defeated(IslandManager.BOSS_ID)
	var via_property: bool = manager.boss_defeated
	manager.free()

	var err: String = _T.assert_true(defeated, "the old scalar promoted into the keyed state")
	if err != "":
		return err
	# The compatibility property has to agree, or devtools and any older reader disagree
	# with the thing actually driving the spawn.
	return _T.assert_true(via_property, "the boss_defeated property reads through to it")


func test_a_keyed_save_round_trips() -> String:
	var manager := IslandManager.new()
	manager.bosses_defeated[IslandManager.BOSS_ID] = true

	var payload: Dictionary = manager.saveObject()
	var reloaded := IslandManager.new()
	reloaded.loadObject(payload)

	var keyed: bool = reloaded.is_boss_defeated(IslandManager.BOSS_ID)
	# Still written for a build rolled back to the previous loader. One bool, and it is the
	# difference between a rollback being safe and a killed boss coming back.
	var scalar_present: bool = payload.get("boss_defeated", false) == true
	manager.free()
	reloaded.free()

	var err: String = _T.assert_true(keyed, "the keyed state survived the round trip")
	if err != "":
		return err
	return _T.assert_true(scalar_present, "and the legacy scalar is written alongside it")


func test_an_undefeated_island_is_reported_undefeated() -> String:
	# The negative case, so the two above cannot pass by everything reading true.
	var manager := IslandManager.new()
	var fresh: bool = manager.is_boss_defeated(IslandManager.BOSS_ID)
	var unknown: bool = manager.is_boss_defeated("no_such_island")
	manager.free()

	var err: String = _T.assert_false(fresh, "a fresh manager has no dead bosses")
	if err != "":
		return err
	return _T.assert_false(unknown, "and an island with no boss is not 'defeated'")


func test_every_boss_definition_names_a_real_island() -> String:
	# BOSSES and ISLANDS are two tables that have to agree. A boss keyed to an island id
	# that does not exist never spawns, and nothing reports it.
	for island_id in IslandManager.BOSSES:
		if IslandManager._definition_for(island_id).is_empty():
			return _T.assert_true(false, "boss '%s' names no island in ISLANDS" % island_id)
		var boss: Dictionary = IslandManager.BOSSES[island_id]
		if not EnemyRegistry.has_type(boss["type"]):
			return _T.assert_true(false,
				"boss '%s' names unregistered enemy type '%s'" % [island_id, boss["type"]])
	return ""
