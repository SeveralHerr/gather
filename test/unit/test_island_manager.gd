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


func _reachable_from_origin(world: Dictionary) -> Dictionary:
	# Untyped: cell_nearest_to returns null for an empty set, so it has no inferable type.
	var start = TileMapHandler.cell_nearest_to(world.keys(), Vector2i.ZERO)
	if start == null:
		return {}

	var seen := {start: true}
	var frontier := [start]
	while not frontier.is_empty():
		var cell: Vector2i = frontier.pop_back()
		for step in [Vector2i(1, 0), Vector2i(-1, 0), Vector2i(0, 1), Vector2i(0, -1)]:
			var next: Vector2i = cell + step
			if world.has(next) and not seen.has(next):
				seen[next] = true
				frontier.append(next)
	return seen


## The one that matters. A stranded island is a dead end the player can see and never
## reach, with nothing logged anywhere.
func test_every_island_connects_to_home_across_many_seeds() -> String:
	var stranded := []

	for i in SEEDS_TO_TRY:
		var seed_value := 1000 + i * 7919
		manager.islands_seed = seed_value

		var home := _home_land(seed_value)
		var anchor := IslandManager.main_body(home)
		var world := home.duplicate()
		var taken := []
		var centres := {}

		for definition in IslandManager.placement_order():
			var angle: float = manager._choose_angle(definition["distance"], taken, anchor)
			taken.append(angle)
			var centre: Vector2i = IslandManager._cell_along(angle, definition["distance"])
			centres[definition["id"]] = centre
			var cells := IslandManager.island_cells(centre, definition["radius"], seed_value, definition["id"])
			for cell in cells:
				world[cell] = true
			for cell in manager._isthmus_cells(centre, definition["radius"], angle, anchor, cells):
				world[cell] = true

		var reachable := _reachable_from_origin(world)
		for id in centres:
			if not reachable.has(centres[id]):
				stranded.append("seed %d: %s at %s" % [seed_value, id, centres[id]])

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

		var anchor := IslandManager.main_body(_home_land(seed_value))
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
