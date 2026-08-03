extends RefCounted

## Covers TileMapHandler.parse_tile_payload (gather-5my).
##
## The bug this guards was not that a corrupt tile line failed to load. It was that
## loadObject cleared layers 1-3 across the whole map *before* parsing anything, then
## indexed straight into the payload — so one bad line raised, the method aborted
## silently (a raise in a `-> void` is indistinguishable from a clean return), and
## `late_load = true` at the bottom was never reached. The player lost every building
## they had placed, plus every chest/station/turret payload waiting in SaveLoad.loads.
##
## Everything below therefore asserts the same thing from different angles: a bad entry
## costs exactly one tile and never the run.

## Injected by the runner (tools/run_tests.gd).
var _T


## The shape main.gd writes: each tile is a JSON string inside the JSON payload.
func _entry(type: int, x: int, y: int) -> String:
	return JSON.stringify({"type": type, "x": x, "y": y})


func test_a_well_formed_payload_round_trips() -> String:
	var parsed: Array = TileMapHandler.parse_tile_payload([
		_entry(5, 3, -7),
		_entry(22, 0, 0),
	])

	var size_check: String = _T.assert_eq(parsed.size(), 2, "both entries should survive")
	if size_check != "":
		return size_check

	var type_check: String = _T.assert_eq(parsed[0]["type"], 5, "type should round trip")
	if type_check != "":
		return type_check

	var x_check: String = _T.assert_eq(parsed[0]["x"], 3, "x should round trip")
	if x_check != "":
		return x_check

	return _T.assert_eq(parsed[0]["y"], -7, "a negative y should round trip")


func test_coordinates_come_back_as_ints_not_floats() -> String:
	# JSON has a single number type, so every one of these parses back as a float and
	# Vector2i(float, float) would quietly truncate rather than fail. Assert the cast.
	var parsed: Array = TileMapHandler.parse_tile_payload([_entry(5, 12, -4)])

	var x_check: String = _T.assert_true(
		typeof(parsed[0]["x"]) == TYPE_INT, "x should be an int, got %s" % [typeof(parsed[0]["x"])])
	if x_check != "":
		return x_check

	return _T.assert_true(
		typeof(parsed[0]["type"]) == TYPE_INT, "type should be an int, got %s" % [typeof(parsed[0]["type"])])


## EXPECTED STDERR: one "skipping an unparseable tile entry" warning. That is the
## assertion passing, not a failure.
func test_an_unparseable_entry_costs_one_tile_not_the_payload() -> String:
	var parsed: Array = TileMapHandler.parse_tile_payload([
		_entry(5, 1, 1),
		"{not json at all",
		_entry(7, 2, 2),
	])

	var size_check: String = _T.assert_eq(parsed.size(), 2, "the two good entries should survive")
	if size_check != "":
		return size_check

	return _T.assert_eq(parsed[1]["type"], 7, "the entry AFTER the bad one must still be read")


## EXPECTED STDERR: three "skipping a malformed tile entry" warnings.
func test_entries_missing_any_required_key_are_dropped() -> String:
	var parsed: Array = TileMapHandler.parse_tile_payload([
		JSON.stringify({"x": 1, "y": 1}),          # no type
		JSON.stringify({"type": 5, "y": 1}),       # no x
		JSON.stringify({"type": 5, "x": 1}),       # no y
		_entry(9, 4, 4),
	])

	var size_check: String = _T.assert_eq(parsed.size(), 1, "only the complete entry should survive")
	if size_check != "":
		return size_check

	return _T.assert_eq(parsed[0]["type"], 9, "the surviving entry should be the complete one")


## EXPECTED STDERR: two "skipping a malformed tile entry" warnings.
func test_entries_that_are_not_dictionaries_are_dropped() -> String:
	# A saveObject() that raised writes an empty dict; a truncated file can leave a bare
	# scalar. Neither may reach node["type"].
	var parsed: Array = TileMapHandler.parse_tile_payload([
		"[1, 2, 3]",
		"42",
		_entry(3, 0, 0),
	])

	return _T.assert_eq(parsed.size(), 1, "only the dictionary entry should survive")


func test_an_empty_payload_is_not_an_error() -> String:
	# Distinct from a MISSING tiles array, which loadObject handles separately by skipping
	# the clear entirely. An empty-but-present array is a legitimate save of an empty world.
	return _T.assert_eq(TileMapHandler.parse_tile_payload([]).size(), 0, "empty in, empty out")


## EXPECTED STDERR: two "unparseable" warnings ("" and "{") and one "malformed" ("{}").
func test_a_payload_of_nothing_but_garbage_returns_empty_rather_than_raising() -> String:
	# The whole point: the caller gets an empty list and goes on to clear and replay
	# nothing, instead of aborting with the layers already wiped.
	var parsed: Array = TileMapHandler.parse_tile_payload(["", "{", JSON.stringify({})])

	return _T.assert_eq(parsed.size(), 0, "garbage in, empty out, no raise")
