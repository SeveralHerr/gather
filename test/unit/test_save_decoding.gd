extends RefCounted

## SaveLoad.decode_entries — the one place that knows a saved sub-list can hold either
## shape (gather-usv).
##
## Until format v3 every sub-list inside a save entry held JSON strings, inside a payload
## that _save() then stringified again: tiles, recipes, unlocked resources, islands,
## enemies, ground drops, chest slots, turret bullets. The inner layer bought nothing and
## cost a JSON parser per entry — for main.gd's tile list, thousands per load.
##
## Detection here is structural and never by version number. That is load-bearing rather
## than stylistic: a v2 file copied verbatim into a slot by the migration is still v2 on
## disk while the running build writes v3, so both shapes genuinely coexist and a
## version-keyed reader would misread one of them.

## Injected by the runner (tools/run_tests.gd).
var _T


func test_the_new_shape_passes_through_untouched() -> String:
	var out: Array = SaveLoad.decode_entries([{"type": 5, "x": 1, "y": 2}])

	var size_check: String = _T.assert_eq(out.size(), 1, "one entry in, one out")
	if size_check != "":
		return size_check

	return _T.assert_eq(int(out[0]["type"]), 5, "and its fields are readable")


func test_the_old_shape_is_parsed() -> String:
	var out: Array = SaveLoad.decode_entries([JSON.stringify({"type": 7, "x": 3, "y": 4})])

	var size_check: String = _T.assert_eq(out.size(), 1, "a JSON string decodes to one entry")
	if size_check != "":
		return size_check

	return _T.assert_eq(int(out[0]["type"]), 7, "with the same fields as the new shape")


func test_both_shapes_can_appear_in_one_list() -> String:
	# Not hypothetical: the migration copies a v2 file into a slot verbatim, so a v3 build
	# reads v2 sub-lists. A version-keyed reader would get exactly one of these wrong.
	var out: Array = SaveLoad.decode_entries([
		JSON.stringify({"type": 1}),
		{"type": 2},
		JSON.stringify({"type": 3}),
	])

	var size_check: String = _T.assert_eq(out.size(), 3, "all three decode")
	if size_check != "":
		return size_check

	var types: Array = []
	for entry in out:
		types.append(int(entry["type"]))

	return _T.assert_eq(str(types), str([1, 2, 3]), "in order, regardless of shape")


## EXPECTED STDERR: one "unparseable sub-entry" warning.
func test_one_unreadable_entry_does_not_take_the_rest_with_it() -> String:
	# The behaviour every one of these call sites lacked: they indexed the parse result
	# directly, so a corrupt entry raised and dropped everything after it too.
	var out: Array = SaveLoad.decode_entries([
		{"type": 1},
		"{not json",
		{"type": 3},
	])

	var size_check: String = _T.assert_eq(out.size(), 2, "the two good entries survive")
	if size_check != "":
		return size_check

	return _T.assert_eq(int(out[1]["type"]), 3, "including the one AFTER the bad entry")


## EXPECTED STDERR: one "not a dictionary" warning.
func test_a_string_that_parses_to_a_non_dictionary_is_dropped() -> String:
	var out: Array = SaveLoad.decode_entries([JSON.stringify([1, 2, 3]), {"type": 9}])

	return _T.assert_eq(out.size(), 1, "a JSON array is not an entry")


## EXPECTED STDERR: two "unexpected type" warnings.
func test_entries_of_unexpected_types_are_dropped() -> String:
	var out: Array = SaveLoad.decode_entries([42, null, {"type": 1}])

	return _T.assert_eq(out.size(), 1, "only the dictionary survives")


func test_a_dictionary_keyed_container_is_accepted() -> String:
	# pick_up_manager and bone_turret store their sub-lists as a Dictionary keyed by index
	# rather than as an Array. Both are ordered containers of entries as far as this is
	# concerned, and the callers should not each have to unwrap one.
	var out: Array = SaveLoad.decode_entries({
		"0": JSON.stringify({"itemType": 5}),
		"1": {"itemType": 6},
	})

	return _T.assert_eq(out.size(), 2, "both entries decode out of a keyed container")


func test_an_empty_or_absent_list_decodes_to_nothing() -> String:
	var empty: String = _T.assert_eq(SaveLoad.decode_entries([]).size(), 0, "empty in, empty out")
	if empty != "":
		return empty

	# What `loadedDict.get("recipes", [])` yields for a payload that never had the key.
	return _T.assert_eq(SaveLoad.decode_entries(null).size(), 0, "a null list is not an error")


# --- the tile payload, which is 90% of a save by volume -----------------------

func test_tile_entries_decode_from_both_shapes() -> String:
	var old_shape: Array = TileMapHandler.parse_tile_payload(
		[JSON.stringify({"type": 16, "x": -3, "y": 0})])
	var new_shape: Array = TileMapHandler.parse_tile_payload(
		[{"type": 16, "x": -3, "y": 0}])

	var old_check: String = _T.assert_eq(old_shape.size(), 1, "a pre-v3 tile still decodes")
	if old_check != "":
		return old_check

	var new_check: String = _T.assert_eq(new_shape.size(), 1, "and so does a v3 tile")
	if new_check != "":
		return new_check

	return _T.assert_eq(
		str(old_shape[0]), str(new_shape[0]), "and both produce an identical entry")


func test_a_v3_tile_still_comes_back_with_int_coordinates() -> String:
	# JSON has one number type, so a nested dictionary that has been through a file still
	# arrives with floats. The cast has to survive the de-encoding.
	var parsed: Array = TileMapHandler.parse_tile_payload([{"type": 16.0, "x": -3.0, "y": 0.0}])

	return _T.assert_true(
		typeof(parsed[0]["x"]) == TYPE_INT, "x is an int, got %s" % [typeof(parsed[0]["x"])])
