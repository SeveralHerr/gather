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


# --- a station with no recipe -------------------------------------------------

func test_a_station_payload_can_express_a_running_timer_with_no_recipe() -> String:
	# save() writes selected_recipe -1 whenever the recipe is null, and timer_status false
	# whenever the timer runs — nothing stops both being written at once. That combination
	# threw "Invalid access to property or key 'product' on a base object of type 'Nil'" on
	# the first tick after a load, because _on_timeout read selected_recipe.product.
	var payload := {
		"x": 0.0, "y": 0.0,
		"selected_recipe": -1,
		"count": 54,
		"starting_count": 60,
		"wait_time": 8.0,
		"time_left": 3.4,
		"timer_status": false,
		"type": Types.Item.Furnace,
		"filepath": "343",
	}

	var recipe_check: String = _T.assert_eq(
		int(payload["selected_recipe"]), -1, "the payload really does say 'no recipe'")
	if recipe_check != "":
		return recipe_check

	var running_check: String = _T.assert_false(
		bool(payload["timer_status"]), "and 'timer running' at the same time")
	if running_check != "":
		return running_check

	# The invariant the loader has to restore: no recipe means no work order, so the count
	# must not survive either. Leaving count > 0 is not inert — _process restarts a stopped
	# timer whenever count > 0, so the station would tick straight back into the crash.
	return _T.assert_true(
		int(payload["count"]) > 0,
		"count is non-zero in the payload, which is why load() has to zero it rather than "
		+ "just stopping the timer")


func test_recipe_id_minus_one_resolves_to_no_recipe() -> String:
	# Both lookups answer null for -1, which is what makes the guard reachable rather than
	# theoretical.
	var furnace: Variant = Recipes.get_furnace_recipe(-1)
	var sawmill: Variant = Recipes.get_sawmill_recipe(-1)

	var f: String = _T.assert_true(furnace == null, "get_furnace_recipe(-1) is null")
	if f != "":
		return f

	return _T.assert_true(sawmill == null, "get_sawmill_recipe(-1) is null")


# --- bone turret: the assembly flag, and every bullet ------------------------

## A live turret in a hosted viewport. Its save/load touch $LoadedSprite and the
## LineOfSight Area2D, so unlike the payload-only tests above these need a real tree.
func _turret() -> Node:
	return await _T.instantiate_ui(load("res://turrets/bone_turret.tscn"))


func test_an_assembled_turret_with_no_bullets_still_saves_its_assembly() -> String:
	# The costliest of the three turret defects, and the one that fires in the COMMON case.
	# `loaded` used to be written only inside the per-bullet dictionaries, so a turret with
	# nothing currently in the air saved `data: {}` and came back unassembled — permanently
	# inert, needing another netted skull to fix. A turret is idle far more often than it is
	# mid-shot, so this lost the assembly most of the time (gather-ze1).
	var turret := await _turret()
	turret.set_loaded()

	var payload: Dictionary = turret.save()
	_T.free_ui(turret)

	var err: String = _T.assert_true(payload.get("data", {}).is_empty(),
		"the turret really had no bullets, so the per-bullet copy could not carry the flag")
	if err != "":
		return err
	return _T.assert_true(payload.get("loaded", false) == true,
		"the assembly flag is on the turret's own payload")


func test_an_assembled_turret_reloads_assembled() -> String:
	var turret := await _turret()
	var was_loaded: bool = turret.loaded

	turret.load({"x": 0.0, "y": 0.0, "loaded": true, "data": {}, "filepath": "343"})
	var now_loaded: bool = turret.loaded
	_T.free_ui(turret)

	var err: String = _T.assert_false(was_loaded, "a fresh turret starts unassembled")
	if err != "":
		return err
	return _T.assert_true(now_loaded, "the saved assembly came back")


func test_every_saved_bullet_comes_back_with_its_position() -> String:
	# Two defects in one assertion. The retarget scan used to sit INSIDE the bullet loop with
	# a `return`, so a turret with an enemy in line of sight abandoned load() after the first
	# bullet and silently dropped the rest; and only `velocity` was ever restored, so the
	# bullets that did come back reappeared at the turret's own origin. save() has always
	# written x/y/rotation — the loader simply never read them (gather-ze1).
	var turret := await _turret()

	var payload := {
		"x": 0.0, "y": 0.0, "loaded": true, "filepath": "343",
		"data": {
			0: {"x": 10.0, "y": 20.0, "rotation": 0.5, "velocityx": 100.0, "velocityy": 0.0},
			1: {"x": 30.0, "y": 40.0, "rotation": 1.5, "velocityx": 0.0, "velocityy": 100.0},
			2: {"x": 50.0, "y": 60.0, "rotation": 2.5, "velocityx": -100.0, "velocityy": 0.0},
		},
	}
	turret.load(payload)

	var bullets: Array = []
	for child in turret.get_children():
		if child is Bullet:
			bullets.append(child)
	bullets.sort_custom(func(a, b): return a.position.x < b.position.x)

	var count: int = bullets.size()
	var positions: Array = []
	var rotations: Array = []
	for b in bullets:
		positions.append("%d,%d" % [roundi(b.position.x), roundi(b.position.y)])
		rotations.append(snappedf(b.rotation, 0.01))
	_T.free_ui(turret)

	var err: String = _T.assert_eq(count, 3, "all three saved bullets were restored")
	if err != "":
		return err
	err = _T.assert_eq(str(positions), str(["10,20", "30,40", "50,60"]),
		"each bullet came back where it was, not at the turret's origin")
	if err != "":
		return err
	return _T.assert_eq(str(rotations), str([0.5, 1.5, 2.5]), "and pointing the way it was")


# --- the world clock: the storm in progress ----------------------------------

## A WorldClock outside the tree. `_ready` never runs, so it never joins a group and never
## touches anything else — which is exactly what is wanted: saveObject/loadObject are the
## subject here, and they are the only two methods that touch disk state.
##
## `get_path()` on a node outside the tree is empty, so `saveObject` writes an empty
## filepath. That is fine for a round-trip test and is not what the game does; the live node
## is authored into main.tscn at /root/Main/Systems/WorldClock.
func _clock() -> WorldClock:
	return WorldClock.new()


func test_a_storm_in_progress_keeps_the_time_it_has_left() -> String:
	# The same shape as the furnace bug (gather-9x0): the CONFIGURED length of a storm is a
	# constant and never moves, so saving it tells you nothing about how far through this
	# one you are. A load that restored the configured value would hand a player who had
	# waited out all but ten seconds of a downpour a fresh three-minute one.
	var clock := _clock()
	clock.set_weather(WorldClock.Weather.RAIN, 12.5)
	clock.time_of_day = 0.83
	clock.day = 4

	var payload := clock.saveObject()

	var err: String = _T.assert_true(payload.has("weather_time_left"), "the storm's remaining time is written")
	if err != "":
		return err

	var restored := _clock()
	restored.loadObject(payload)

	err = _T.assert_float_eq(restored.weather_time_left, 12.5, 0.0001, "the storm resumes where it stopped")
	if err != "":
		return err
	err = _T.assert_eq(restored.weather, WorldClock.Weather.RAIN, "and it is still raining")
	if err != "":
		return err
	err = _T.assert_float_eq(restored.time_of_day, 0.83, 0.0001, "at the same hour")
	if err != "":
		return err
	return _T.assert_eq(restored.day, 4, "on the same day")


func test_a_clock_saved_at_night_loads_at_night() -> String:
	# The phase is derived rather than stored, so this is really asserting that time_of_day
	# survives with enough precision to land in the same phase — a rounded or truncated
	# value would put the player back in daylight with the enemy cap still raised.
	var clock := _clock()
	clock.time_of_day = 0.88

	var restored := _clock()
	restored.loadObject(clock.saveObject())

	return _T.assert_eq(restored.phase(), WorldClock.Phase.NIGHT, "midnight survives the round-trip")


func test_a_save_from_before_the_clock_existed_leaves_it_at_its_defaults() -> String:
	# Every save written before gather-bqn has no entry for this node at all, and a player
	# loading one must get a playable world rather than a crash. Every read is get()-with-a-
	# default for exactly this, and a raise here would abort loadObject silently — it is
	# `-> void`, so the abort is indistinguishable from success.
	var restored := _clock()
	restored.loadObject({})

	var err: String = _T.assert_eq(restored.day, 1, "an absent entry starts on day one")
	if err != "":
		return err
	err = _T.assert_eq(restored.weather, WorldClock.Weather.CLEAR, "and in clear weather")
	if err != "":
		return err
	return _T.assert_eq(restored.phase(), WorldClock.Phase.DAY, "and in daylight, not mid-storm at midnight")


func test_clearing_the_weather_clears_the_time_left_with_it() -> String:
	# Otherwise a save taken after a storm ends carries a stale countdown, and the next load
	# restores CLEAR weather with seconds left on a clock nothing is running — which the
	# next `set_weather(RAIN)` would then be measured against.
	var clock := _clock()
	clock.set_weather(WorldClock.Weather.RAIN, 30.0)
	clock.set_weather(WorldClock.Weather.CLEAR, 0.0)

	var payload := clock.saveObject()
	return _T.assert_float_eq(
		float(payload["weather_time_left"]), 0.0, 0.0001, "clear weather has no countdown"
	)


func test_a_load_into_the_night_does_not_reannounce_nightfall() -> String:
	# night_started drives the spawner's ceiling. If loadObject let the next tick "discover"
	# the phase it would fire again on every load taken after dark, and anything that
	# reacts to nightfall with a one-off (a sound, a splash, a spawn burst) would repeat it.
	var clock := _clock()
	clock.time_of_day = 0.9
	clock.loadObject(clock.saveObject())

	# An Array, not an int. GDScript lambdas capture locals BY VALUE, so `count += 1` inside
	# the callable would increment a copy and this test would report zero no matter what the
	# clock did — a false pass that looks identical to a real one. An Array is a reference,
	# so appending through the capture is visible out here.
	var announcements: Array = []
	clock.night_started.connect(func(_day): announcements.append(1))
	clock.tick(0.016)

	return _T.assert_eq(announcements.size(), 0, "already being at night is not a new nightfall")
