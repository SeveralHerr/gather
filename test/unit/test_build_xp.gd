extends RefCounted

## The place/destroy xp faucet and the ledger that closed it (`gather-5s5`).
##
## XP_BUILD is priced on the premise that a placed tile was gathered or crafted first, so
## the placement is the tail of a chain that has already paid out. DestroyManager breaks
## that premise: it hands the tile straight back as a pickup. Place, destroy, repeat on one
## square minted ~1.33 xp a cycle off a single item, forever, without gathering anything.
##
## These tests drive a detached LevelUpManager. That works because every tree-dependent
## thing add_xp touches guards a null tree — SplashText._get_container returns null,
## _refresh_xp_bar finds no player, sync_player_stats returns early. The awards here are
## deliberately kept well under XP_FIRST_LEVEL so no level-up fires: _splash_level_up uses
## get_tree().create_timer(), which a detached node genuinely cannot do.

var _T

var manager: LevelUpManager


func setup() -> void:
	manager = LevelUpManager.new()


func teardown() -> void:
	if manager != null:
		manager.free()
		manager = null


func test_building_on_a_fresh_cell_pays() -> String:
	var granted := manager.award_build_xp(Vector2i(3, -7))

	var err: String = _T.assert_eq(granted, LevelUpManager.XP_BUILD, "a first placement pays XP_BUILD")
	if err != "":
		return err

	return _T.assert_eq(manager.xp, LevelUpManager.XP_BUILD, "and the xp actually lands")


func test_rebuilding_the_same_cell_pays_nothing() -> String:
	# The exploit, exactly: one item, placed and destroyed and placed again on one square.
	var cell := Vector2i(3, -7)
	manager.award_build_xp(cell)
	var xp_after_first := manager.xp

	for _cycle in 20:
		var granted := manager.award_build_xp(cell)
		if granted != 0:
			return "cycle %d on an already-built cell paid %d xp" % [_cycle, granted]

	return _T.assert_eq(
		manager.xp, xp_after_first,
		"twenty place/destroy cycles on one cell moved the xp total"
	)


func test_building_somewhere_new_still_pays() -> String:
	# The guard on the guard. Paying per cell must not turn into paying once ever, or
	# building stops being worth xp the moment a player has placed a single tile.
	manager.award_build_xp(Vector2i(0, 0))

	var granted := manager.award_build_xp(Vector2i(0, 1))

	return _T.assert_eq(granted, LevelUpManager.XP_BUILD, "an untouched cell pays like any first placement")


func test_the_ledger_survives_a_save_load_roundtrip() -> String:
	# Without this the faucet reopens on the first load, which is the failure mode that
	# would never show up in a test session and always show up in a real one.
	manager.award_build_xp(Vector2i(3, -7))
	manager.award_build_xp(Vector2i(-12, 40))

	var saved := manager.saveObject()

	var reloaded := LevelUpManager.new()
	reloaded.loadObject(saved)
	var granted := reloaded.award_build_xp(Vector2i(3, -7))
	var kept: int = reloaded.built_cells.size()
	reloaded.free()

	var err: String = _T.assert_eq(kept, 2, "both built cells came back")
	if err != "":
		return err

	return _T.assert_eq(granted, 0, "a cell built before the save does not pay again after it")


func test_negative_coordinates_round_trip_intact() -> String:
	# The ledger is serialised as "x,y" strings because entries are JSON-stringified and
	# JSON has no vector type. Negative cells are half the island and the obvious thing for
	# a hand-rolled parse to mangle into a cell that never matches again.
	manager.award_build_xp(Vector2i(-12, -40))

	var reloaded := LevelUpManager.new()
	reloaded.loadObject(manager.saveObject())
	var has_cell: bool = reloaded.built_cells.has(Vector2i(-12, -40))
	reloaded.free()

	return _T.assert_true(has_cell, "the negative cell came back as the same Vector2i")


func test_a_save_written_before_the_ledger_loads_clean() -> String:
	# Every existing saveFile predates gather-5s5 and has no "built_cells" key at all.
	var legacy := {
		"filepath": "/root/Main/Systems/LevelUpManager",
		"taken": [],
		"points": 0,
		"level": 1,
		"xp": 5,
		"next_level": LevelUpManager.XP_FIRST_LEVEL,
	}

	manager.loadObject(legacy)

	return _T.assert_eq(manager.built_cells.size(), 0, "an absent key loads as an empty ledger, not an error")
