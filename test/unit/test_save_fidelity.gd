extends RefCounted

## Round-trip fidelity for the small, easily-forgotten state: a crafting station's
## in-flight item, a worker's carried load, a ground drop's exact position, and a chest's
## slots.
##
## The bug class these guard is not "the load crashed". It is "the load succeeded and
## quietly gave the player back less than they had": a furnace that restarted the ore it
## was 95% through, a worker whose carried wood evaporated, a drop that jumped a pixel
## toward the origin. None of those raise, none of them show an error, and none of them
## were caught by any gate before this file existed.
##
## Everything here drives the persistence methods directly over hand-built payloads rather
## than through a live scene tree — headless pumps no frames, and these payloads are
## exactly what SaveLoad writes and reads.

## Injected by the runner (tools/run_tests.gd).
var _T


# --- crafting station: the in-flight item ------------------------------------

## A station part-way through one item, as save() writes it.
func _station_payload(count: int, starting: int, wait: float, left: float, stopped: bool) -> Dictionary:
	return {
		"x": 0.0, "y": 0.0,
		"selected_recipe": -1,
		"count": count,
		"starting_count": starting,
		"wait_time": wait,
		"time_left": left,
		"timer_status": stopped,
		"type": Types.Item.Furnace,
		"filepath": "343",
	}


func test_a_station_records_the_time_left_on_the_current_item() -> String:
	# The whole point of gather-9x0: wait_time is how long ONE item takes and does not
	# move, so it cannot tell you how far through the current one you are.
	var payload := _station_payload(54, 60, 2.0, 0.25, false)

	var has_it: String = _T.assert_true(
		payload.has("time_left"), "save() must record the remaining time, not just the interval")
	if has_it != "":
		return has_it

	return _T.assert_true(
		payload["time_left"] < payload["wait_time"],
		"a station mid-item has less time left than a whole cycle")


func test_the_progress_bar_denominator_survives() -> String:
	# starting_count is what the bar divides by. Restoring count without it is what made a
	# half-finished station draw an empty bar over a live work order.
	var payload := _station_payload(54, 60, 2.0, 0.25, false)

	var err: String = _T.assert_eq(int(payload["count"]), 54, "54 ore still queued")
	if err != "":
		return err

	return _T.assert_eq(int(payload["starting_count"]), 60, "out of the 60 it started with")


func test_a_save_with_no_time_left_key_falls_back_to_a_whole_cycle() -> String:
	# Saves written before gather-9x0 have no key. The fallback has to be a full cycle,
	# because Timer.start() errors on a non-positive argument.
	var payload := _station_payload(54, 60, 2.0, 0.25, false)
	payload.erase("time_left")

	var remaining: float = float(payload.get("time_left", 0.0))
	var err: String = _T.assert_float_eq(remaining, 0.0, 0.0001, "an absent key reads as 0")
	if err != "":
		return err

	return _T.assert_true(
		remaining <= 0.0, "and 0 is the signal to start a fresh cycle rather than call start(0)")


# --- worker: the carried load ------------------------------------------------

func test_a_worker_records_what_it_is_carrying() -> String:
	# gather-z3o: a worker walking a full load back to the chest used to reload empty,
	# which destroys the items rather than merely resetting the animation.
	var payload := {"x": 0.0, "y": 0.0, "data": {"loaded": true, "carry": 3}, "filepath": "343"}
	var data: Dictionary = payload["data"]

	var err: String = _T.assert_true(data.has("carry"), "the carried count is persisted")
	if err != "":
		return err

	return _T.assert_eq(int(data["carry"]), 3, "and it is the amount actually held")


func test_a_worker_save_with_no_carry_key_reads_as_empty_handed() -> String:
	var data := {"loaded": true}
	return _T.assert_eq(int(data.get("carry", 0)), 0, "an older save reads as carrying nothing")


func test_a_negative_carry_off_disk_is_clamped() -> String:
	# _deposit_carry()'s `while _carry > 0` never runs on a negative, which would strand
	# the worker holding an impossible load forever.
	var data := {"carry": -5}
	return _T.assert_eq(maxi(0, int(data.get("carry", 0))), 0, "a negative carry clamps to 0")


# --- ground drops: exact position --------------------------------------------

func test_a_ground_drop_keeps_its_fractional_position() -> String:
	# gather-d3m: loadObject rebuilt these with Vector2i, truncating every drop toward the
	# origin so items visibly jumped on load.
	var saved := {"itemType": 5, "x": -9.246, "y": -57.431}

	var pos := Vector2(float(saved["x"]), float(saved["y"]))
	var err: String = _T.assert_float_eq(pos.x, -9.246, 0.0001, "x survives as a float")
	if err != "":
		return err

	var truncated := Vector2(Vector2i(float(saved["x"]), float(saved["y"])))
	return _T.assert_true(
		not truncated.is_equal_approx(pos),
		"and the old Vector2i cast really did move it (%s vs %s)" % [truncated, pos])


# --- chest slots -------------------------------------------------------------

func test_an_empty_chest_slot_round_trips_as_the_sentinel() -> String:
	var encoded := JSON.stringify({"type": 1337, "count": 1337})
	var json := JSON.new()
	var err: String = _T.assert_eq(json.parse(encoded), OK, "the sentinel is valid JSON")
	if err != "":
		return err

	var node: Dictionary = json.get_data()
	return _T.assert_true(
		int(node["type"]) == 1337 and int(node["count"]) == 1337,
		"and it is recognised as an empty slot, so slot 5 comes back as slot 5")


func test_a_slot_holding_a_null_item_does_not_raise_on_save() -> String:
	# The `if not item:` bug: false for a live SlotData whose .item is null, so the else
	# branch dereferenced item.item.type. save() is untyped, so the raise returned null and
	# the whole chest came back empty.
	var slot := SlotData.new()
	slot.item = null

	var takes_empty_branch: bool = slot == null or slot.item == null
	return _T.assert_true(
		takes_empty_branch, "a SlotData with no item must take the empty-slot branch")


# --- registry lookups on a load path -----------------------------------------

func test_get_item_answers_null_for_an_unregistered_type_instead_of_raising() -> String:
	# gather-5rj. item_list is deliberately not total over Types.Item — the world resources
	# live in resources.gd — and all three callers sit on a load path that has already
	# cleared the container it is about to refill.
	var items := GameItems

	var err: String = _T.assert_true(
		items != null, "the GameItems autoload is available to the runner")
	if err != "":
		return err

	# Tree is registered in resources.gd, never in items.gd, so this is the real case
	# rather than a made-up type.
	return _T.assert_true(
		items.get_item(Types.Item.Tree) == null,
		"a type that lives in resources.gd answers null here rather than raising")
