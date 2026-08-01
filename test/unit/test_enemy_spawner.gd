extends RefCounted

## Covers the parts of continuous spawning that are decidable without a running
## game: the island-scaled population cap, the cadence jitter, the no-spawn radius
## around the player, and the save payload's tolerance of pre-wave-removal saves.

var _T


func test_the_cap_scales_with_the_island() -> String:
	# 0.02 enemies per grass tile: a 400-tile island carries 8.
	var err: String = _T.assert_eq(EnemySpawner.cap_for_land_tiles(400), 8, "400 tiles carries 8 enemies")
	if err != "":
		return err

	return _T.assert_eq(EnemySpawner.cap_for_land_tiles(900), 18, "900 tiles carries 18 enemies")


func test_the_cap_is_monotonic_in_island_size() -> String:
	# Buying land must never *reduce* the enemy population — that would make the
	# purchase read as a stealth difficulty reduction.
	var previous := 0
	for tiles in [0, 50, 150, 300, 600, 1200, 5000]:
		var cap := EnemySpawner.cap_for_land_tiles(int(tiles))
		if cap < previous:
			return _T.assert_true(false, "cap fell from %d to %d at %d tiles" % [previous, cap, tiles])
		previous = cap

	return ""


func test_a_starter_island_still_gets_enemies() -> String:
	# Below the floor the density rounds to 0 or 1 and combat effectively stops.
	var err: String = _T.assert_gte(
		EnemySpawner.cap_for_land_tiles(0), EnemySpawner.MIN_ENEMY_CAP, "an empty island still allows the floor"
	)
	if err != "":
		return err

	return _T.assert_gte(EnemySpawner.cap_for_land_tiles(20), EnemySpawner.MIN_ENEMY_CAP, "a tiny island uses the floor")


func test_a_bought_out_island_is_still_capped() -> String:
	# Without the ceiling, enemies the player never kills accumulate until the
	# frame rate collapses.
	return _T.assert_eq(
		EnemySpawner.cap_for_land_tiles(100000), EnemySpawner.MAX_ENEMY_CAP, "the ceiling holds at any island size"
	)


func test_the_cadence_stays_inside_its_jitter_band() -> String:
	var lowest: float = EnemySpawner.jittered_interval(0.0)
	var highest: float = EnemySpawner.jittered_interval(1.0)

	var err: String = _T.assert_float_eq(
		lowest, EnemySpawner.SPAWN_INTERVAL - EnemySpawner.SPAWN_JITTER, 0.0001, "the low roll is base minus jitter"
	)
	if err != "":
		return err

	err = _T.assert_float_eq(
		highest, EnemySpawner.SPAWN_INTERVAL + EnemySpawner.SPAWN_JITTER, 0.0001, "the high roll is base plus jitter"
	)
	if err != "":
		return err

	return _T.assert_float_eq(
		EnemySpawner.jittered_interval(0.5), EnemySpawner.SPAWN_INTERVAL, 0.0001, "the middle roll is the base cadence"
	)


func test_the_cadence_never_ramps_away_to_nothing() -> String:
	# The old wave manager multiplied its interval by 0.8 forever and needed a
	# floor to stay playable. There is no ramp now, but the floor is still the
	# guard against a jitter constant being edited past the base.
	for i in range(0, 21):
		var interval: float = EnemySpawner.jittered_interval(float(i) / 20.0)
		if interval < EnemySpawner.MIN_INTERVAL:
			return _T.assert_true(false, "roll %f produced a %f second interval" % [float(i) / 20.0, interval])

	return ""


func test_a_tile_in_the_players_lap_is_rejected() -> String:
	var player_pos := Vector2(100, 100)

	var err: String = _T.assert_true(
		EnemySpawner.is_too_close_to_player(player_pos, player_pos), "the player's own tile is too close"
	)
	if err != "":
		return err

	return _T.assert_true(
		EnemySpawner.is_too_close_to_player(player_pos + Vector2(16, 0), player_pos), "one tile away is too close"
	)


func test_a_tile_across_the_island_is_accepted() -> String:
	var player_pos := Vector2(100, 100)
	var far := player_pos + Vector2(EnemySpawner.MIN_SPAWN_DISTANCE + 1.0, 0)

	return _T.assert_false(EnemySpawner.is_too_close_to_player(far, player_pos), "beyond the radius is allowed")


func test_the_exclusion_radius_is_diagonal_aware() -> String:
	# Distance, not a bounding box: a tile that clears the radius on each axis
	# alone can still be inside it.
	var player_pos := Vector2.ZERO
	var d := EnemySpawner.MIN_SPAWN_DISTANCE * 0.7

	return _T.assert_true(
		EnemySpawner.is_too_close_to_player(Vector2(d, d) * 0.9, player_pos),
		"a diagonal tile inside the radius is rejected"
	)


func test_the_save_payload_no_longer_carries_wave_state() -> String:
	var entry := EnemySpawner.enemy_save_entry(7, true, true, 3, Vector2(12, 34), "Spider")

	var err: String = _T.assert_false(entry.has("wave"), "no wave counter in the payload")
	if err != "":
		return err

	err = _T.assert_false(entry.has("wait_time"), "no spawn interval in the payload")
	if err != "":
		return err

	err = _T.assert_eq(entry["hp"], 7, "health round-trips")
	if err != "":
		return err

	return _T.assert_eq(entry["type"], "Spider", "the enemy type round-trips")


func test_a_save_entry_survives_json() -> String:
	var entry := EnemySpawner.enemy_save_entry(4, false, true, 2, Vector2(-8, 16), "Bone")
	var json := JSON.new()
	if json.parse(JSON.stringify(entry)) != OK:
		return _T.assert_true(false, "the save entry did not round-trip through JSON")

	var restored := EnemySpawner.normalize_enemy_entry(json.get_data())

	var err: String = _T.assert_eq(restored["hp"], 4, "health survives the round trip")
	if err != "":
		return err

	err = _T.assert_false(restored["target"], "a live target survives the round trip")
	if err != "":
		return err

	return _T.assert_float_eq(restored["x"], -8.0, 0.0001, "position survives the round trip")


func test_a_pre_removal_save_still_loads() -> String:
	# saveFiles written by the wave manager carry wave / wait_time on every enemy.
	# Those keys are ignored rather than crashing the load.
	var legacy := {
		"hp": 6,
		"target": true,
		"attack_target": false,
		"drop": 1,
		"x": 5.0,
		"y": 9.0,
		"wave": 12,
		"wait_time": 1.5,
		"type": "Bone",
	}

	var restored := EnemySpawner.normalize_enemy_entry(legacy)

	var err: String = _T.assert_eq(restored["hp"], 6, "the legacy health loads")
	if err != "":
		return err

	err = _T.assert_false(restored.has("wave"), "the wave key does not survive into the loaded entry")
	if err != "":
		return err

	return _T.assert_eq(restored["type"], "Bone", "the legacy type loads")


func test_a_truncated_entry_falls_back_instead_of_crashing() -> String:
	var restored := EnemySpawner.normalize_enemy_entry({"hp": 3})

	var err: String = _T.assert_eq(restored["hp"], 3, "what is present is used")
	if err != "":
		return err

	err = _T.assert_eq(restored["type"], "Bone", "a missing type defaults to a real scene")
	if err != "":
		return err

	err = _T.assert_true(restored["target"], "a missing target defaults to unaware")
	if err != "":
		return err

	return _T.assert_float_eq(restored["y"], 0.0, 0.0001, "a missing position defaults to the origin")
