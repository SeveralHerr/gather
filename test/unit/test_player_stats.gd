extends RefCounted

## Covers the half of the skill tree that turns into numbers: PlayerStats summing
## the taken set, and the XP curve deciding how many of those skills a run can
## actually reach.

var _T

var tree: SkillTree
var stats: PlayerStats


func setup() -> void:
	tree = SkillTree.new()
	stats = PlayerStats.new()


func test_a_fresh_player_sits_at_the_base_values() -> String:
	for stat in PlayerStats.BASE:
		var err: String = _T.assert_float_eq(
			float(stats.get(stat)), float(PlayerStats.BASE[stat]), 0.0001, "%s starts at its base" % stat
		)
		if err != "":
			return err

	return ""


func test_taking_a_skill_moves_its_stat() -> String:
	stats.recompute({"swift_hands": true}, tree)

	return _T.assert_float_eq(stats.gather_speed_mult, 0.85, 0.0001, "Swift Hands cuts gather time 15%")


func test_effects_from_different_branches_stack() -> String:
	stats.recompute({"bone_sword": true, "tough_hide": true, "light_step": true}, tree)

	var err: String = _T.assert_eq(stats.damage_bonus, 2, "the sword's damage lands")
	if err != "":
		return err

	err = _T.assert_eq(stats.max_health_bonus, 5, "the hide's health lands")
	if err != "":
		return err

	return _T.assert_float_eq(stats.move_speed_mult, 1.15, 0.0001, "light step's speed lands")


func test_recompute_is_idempotent() -> String:
	# recompute() runs on every purchase and again on load. Applying deltas instead
	# of rebuilding from the taken set would double a stat every time.
	var taken := {"swift_hands": true, "bone_sword": true}
	stats.recompute(taken, tree)
	var once := stats.gather_speed_mult
	var once_damage := stats.damage_bonus

	stats.recompute(taken, tree)
	stats.recompute(taken, tree)

	var err: String = _T.assert_float_eq(stats.gather_speed_mult, once, 0.0001, "gather speed does not drift")
	if err != "":
		return err

	return _T.assert_eq(stats.damage_bonus, once_damage, "damage does not drift")


func test_untaking_everything_returns_to_base() -> String:
	stats.recompute({"swift_hands": true, "bountiful": true}, tree)
	stats.recompute({}, tree)

	var err: String = _T.assert_float_eq(stats.gather_speed_mult, 1.0, 0.0001, "gather speed resets")
	if err != "":
		return err

	return _T.assert_float_eq(stats.bonus_yield_chance, 0.0, 0.0001, "yield bonus resets")


func test_the_whole_tree_never_reaches_a_zero_gather_time() -> String:
	# ResourceManager2 clamps to MIN_GATHER_TIME anyway, but a multiplier at or
	# below zero would mean the clamp is the only thing standing between the game
	# and a Timer error, which is not a margin worth relying on.
	var taken := {}
	for id in tree.order:
		taken[id] = true
	stats.recompute(taken, tree)

	return _T.assert_gt(stats.gather_speed_mult, 0.0, "a fully specced player still has a positive gather time")


func test_an_unknown_skill_id_is_survivable() -> String:
	# Loading a save written by a newer build must not wipe the stats that do
	# resolve. This pushes a warning rather than failing.
	stats.recompute({"swift_hands": true, "not_a_real_skill": true}, tree)

	return _T.assert_float_eq(stats.gather_speed_mult, 0.85, 0.0001, "the known skill still applies")


func test_the_xp_curve_climbs() -> String:
	var previous := LevelUpManager.XP_FIRST_LEVEL
	for target_level in range(3, 15):
		var threshold := LevelUpManager.xp_for_level(target_level)
		if threshold <= previous:
			return _T.assert_true(false, "level %d costs no more than the level before" % target_level)
		previous = threshold

	return ""


func test_the_whole_tree_is_reachable_in_one_run() -> String:
	# One point per level, so clearing every node means reaching level (nodes + 1).
	# Under the old doubling curve that threshold was over 20000 XP, against the
	# 1-4 XP a resource node pays. This is the guard against that regressing.
	var levels_needed := tree.order.size() + 1
	var xp_needed := LevelUpManager.xp_for_level(levels_needed)

	return _T.assert_true(
		xp_needed < 500,
		"clearing the tree costs %d XP, which is too far out of reach" % xp_needed
	)


func test_the_first_level_is_cheap() -> String:
	# The first skill should land within the opening minute or the tree does not
	# read as part of the early game at all.
	return _T.assert_true(
		LevelUpManager.XP_FIRST_LEVEL <= 12,
		"the first level costs %d XP" % LevelUpManager.XP_FIRST_LEVEL
	)
