extends RefCounted

## Covers the end-of-run tally: that it counts what it owns, freezes what it must, refuses to
## end twice, and survives a load.
##
## The thing most worth protecting here is the *split*. RunStats deliberately owns only the
## numbers nothing else keeps (kills, nodes, deaths, time) and reads the rest — level, gold,
## land, raids — from whoever owns it. A future edit that "tidies" one of those into a local
## counter would produce a card that is right on the day it is written and wrong after the first
## load, because the owner's value is restored and the shadow copy is not.

var _T


func _stats() -> RunStats:
	var tree: SceneTree = Engine.get_main_loop() as SceneTree
	var stats := RunStats.new()
	# saveObject() calls get_path(), which pushes an error on a node outside the tree — reported
	# as stderr noise rather than as a failure, which is the worst of both.
	tree.root.add_child(stats)
	return stats


func _drop(stats: RunStats) -> void:
	var tree: SceneTree = Engine.get_main_loop() as SceneTree
	tree.root.remove_child(stats)
	stats.free()


# --- counting -----------------------------------------------------------------


func test_it_counts_what_nothing_else_counts() -> String:
	var stats := _stats()

	for _i in 5:
		stats.record_kill()
	for _i in 3:
		stats.record_death()
	stats._on_resource_removed(Vector2i.ZERO, null)
	stats._on_resource_removed(Vector2i.ONE, null)

	var checks := [
		[stats.enemies_killed, 5, "five kills"],
		[stats.deaths, 3, "three deaths"],
		[stats.resources_gathered, 2, "two nodes"],
	]

	for check in checks:
		var err: String = _T.assert_eq(check[0], check[1], check[2])
		if err != "":
			_drop(stats)
			return err

	_drop(stats)
	return ""


# --- ending -------------------------------------------------------------------


func test_the_run_can_only_end_once() -> String:
	var stats := _stats()

	var first := stats.end_run()
	var err: String = _T.assert_true(first, "the first ending ends the run")
	if err != "":
		_drop(stats)
		return err

	# Idempotent because IslandManager re-asserts its bosses after a save is replayed, and a
	# build with a second boss would call this again. Neither may re-show the card.
	var second := stats.end_run()
	var again: String = _T.assert_false(second, "a second ending changes nothing")
	if again != "":
		_drop(stats)
		return again

	var flag: String = _T.assert_true(stats.run_ended_flag, "the run is still over")
	_drop(stats)
	return flag


## The run's score is a historical fact. Once the card is shown the player may choose KEEP
## PLAYING, earn another thousand gold and level up twice — and a card rebuilt from live values
## afterwards would quietly rewrite what the run scored.
func test_the_score_is_frozen_when_the_run_ends() -> String:
	var stats := _stats()
	stats.end_run()

	var frozen_day := stats.ended_day
	var frozen_level := stats.ended_level
	var frozen_gold := stats.ended_gold

	# The world carries on. In the real game this is the player still playing; here it is enough
	# that the numbers the summary reports do not move.
	stats.record_kill()
	stats.record_kill()

	var summary := stats.summary()

	var checks := [
		[int(summary["day"]), frozen_day, "the day is the day it ended on"],
		[int(summary["level"]), frozen_level, "the level is the level it ended at"],
		[int(summary["gold"]), frozen_gold, "the gold is the gold it ended with"],
	]

	for check in checks:
		var err: String = _T.assert_eq(check[0], check[1], check[2])
		if err != "":
			_drop(stats)
			return err

	_drop(stats)
	return ""


func test_the_summary_names_every_field_the_card_draws() -> String:
	# The card reads these by key with `.get(key, 0)`, so a renamed or missing one is not an
	# error — it is a row that silently shows zero forever. This is the only thing that would
	# notice.
	var stats := _stats()
	var summary := stats.summary()

	var required := [
		"cause", "ended", "day", "level", "gold", "play_seconds",
		"enemies_killed", "resources_gathered", "deaths",
		"raids_cleared", "skills_learned", "parcels_bought", "land_radius",
	]

	for key in required:
		var err: String = _T.assert_true(
			summary.has(key), "the summary carries '%s'" % key)
		if err != "":
			_drop(stats)
			return err

	_drop(stats)
	return ""


# --- save fidelity ------------------------------------------------------------


## A run's tally is exactly the kind of thing that looks correct in a diff and silently resets on
## every load. The card is the only place these numbers are ever shown, so a reset would not be
## noticed until the moment it mattered most.
func test_the_tally_survives_a_round_trip() -> String:
	var stats := _stats()
	stats.play_seconds = 812.5
	stats.enemies_killed = 47
	stats.resources_gathered = 613
	stats.deaths = 2
	stats.end_run()
	stats.ended_day = 14
	stats.ended_level = 19
	stats.ended_gold = 3480

	var payload := stats.saveObject()

	var restored := _stats()
	restored.loadObject(payload)

	var checks := [
		[restored.enemies_killed, 47, "kills carried"],
		[restored.resources_gathered, 613, "nodes carried"],
		[restored.deaths, 2, "deaths carried"],
		[restored.run_ended_flag, true, "the run is still over"],
		[restored.ended_day, 14, "the day it ended on carried"],
		[restored.ended_level, 19, "the level carried"],
		[restored.ended_gold, 3480, "the gold carried"],
	]

	for check in checks:
		var err: String = _T.assert_eq(check[0], check[1], check[2])
		if err != "":
			_drop(stats)
			_drop(restored)
			return err

	var time_err: String = _T.assert_float_eq(
		restored.play_seconds, 812.5, 0.001, "time played carried")

	_drop(stats)
	_drop(restored)
	return time_err


## The flag is what stops the boss ending the run a second time, so it is the one field whose
## loss would be visible — as the card reappearing on a world the player already finished.
func test_a_finished_run_stays_finished_across_a_load() -> String:
	var stats := _stats()
	stats.end_run()
	var payload := stats.saveObject()

	var restored := _stats()
	restored.loadObject(payload)

	# ...and ending it again still does nothing, which is the property that actually matters.
	var err: String = _T.assert_false(
		restored.end_run(), "a reloaded finished run cannot be ended again")

	_drop(stats)
	_drop(restored)
	return err


func test_a_save_written_before_run_stats_existed_loads_quietly() -> String:
	var stats := _stats()
	stats.loadObject({})

	var checks := [
		[stats.run_ended_flag, false, "the run is not over"],
		[stats.enemies_killed, 0, "no kills"],
		[stats.deaths, 0, "no deaths"],
	]

	for check in checks:
		var err: String = _T.assert_eq(check[0], check[1], check[2])
		if err != "":
			_drop(stats)
			return err

	_drop(stats)
	return ""


## `typeof(x) == TYPE_BOOL` rather than `x == true`: comparing a String to a bool raises, and a
## raise inside `-> void` aborts the method and abandons every field below it at its constructor
## value — including the frozen score.
func test_a_non_bool_ended_flag_does_not_raise() -> String:
	var stats := _stats()
	stats.loadObject({"run_ended": "yes", "ended_day": 11, "ended_level": 8})

	var err: String = _T.assert_false(
		stats.run_ended_flag, "an unreadable flag reads as 'still running'")
	if err != "":
		_drop(stats)
		return err

	# The real assertion: the reads AFTER the flag still happened.
	var later: String = _T.assert_eq(stats.ended_level, 8, "the fields after the flag carried")
	_drop(stats)
	return later


# --- formatting ---------------------------------------------------------------


func test_durations_read_as_a_person_would_say_them() -> String:
	var cases := [
		[0.0, "0m 00s"],
		[65.0, "1m 05s"],
		[599.0, "9m 59s"],
		[3600.0, "1h 00m"],
		[7845.0, "2h 10m"],
	]

	for case in cases:
		var err: String = _T.assert_eq(
			RunStats.format_duration(case[0]), case[1],
			"%.0f seconds reads as '%s'" % [case[0], case[1]])
		if err != "":
			return err

	# A negative can only arrive from a corrupted save, and "-1m -01s" on the card would be the
	# most alarming possible way to report it.
	return _T.assert_eq(
		RunStats.format_duration(-50.0), "0m 00s", "a negative duration floors at zero")
