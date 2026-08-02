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
	#
	# The bound was 500 while XP_GROWTH was 1.28. It is the ceiling on a deliberate
	# tuning dial, not a measurement, so it moves with the dial: 1.30 puts the tree at
	# 561, and 650 leaves the next turn of the dial room to fail here rather than
	# silently doubling the run again.
	#
	# gather-1n2 quadrupled XP_FIRST_LEVEL and cut XP_GROWTH to 1.19 to slow the opening,
	# which lands the tree at 578 — inside the existing bound, so the bound has not moved.
	# That is the intended outcome and not a coincidence: the pass was constrained to keep
	# the tail where it was and only re-price the early levels. A bound that gets nudged
	# up every time the dial turns is not a guard, so 650 stays until something genuinely
	# argues for a longer run.
	var levels_needed := tree.order.size() + 1
	var xp_needed := LevelUpManager.xp_for_level(levels_needed)

	return _T.assert_true(
		xp_needed < 650,
		"clearing the tree costs %d XP, which is too far out of reach" % xp_needed
	)


func test_the_first_level_is_earned_not_given() -> String:
	# This asserted XP_FIRST_LEVEL <= 12 on the theory that the tree has to appear inside
	# the opening minute to read as part of the early game. gather-1n2 is the counter-
	# example: at 10 XP against a node's flat 1 XP the panel opened before the player had
	# used a pickaxe on more than a handful of things, and the first skill was a reward
	# for nothing. The band is the intent now, not the floor of it — cheap enough that the
	# tree is an early-game system, expensive enough that reaching it was a decision.
	var first := LevelUpManager.XP_FIRST_LEVEL

	var err: String = _T.assert_true(first >= 25, "the first level costs only %d XP" % first)
	if err != "":
		return err

	return _T.assert_true(first <= 60, "the first level costs %d XP, which is a grind" % first)


func test_the_opening_does_not_hand_out_six_points() -> String:
	# The regression that produced gather-1n2, pinned directly: a player reached six
	# banked skill points within minutes of starting. Thresholds are cumulative, so the
	# sixth point is simply the level-7 threshold, and at 10/1.30 it was 39 XP — under
	# forty resource nodes for a third of the tree.
	#
	# 90 is a floor on the *symptom*, not a restatement of the current constants (which
	# put it at 100). It is roughly 2.3x the value that was reported as broken, so any
	# future pair that drifts back toward the old pacing fails here rather than shipping.
	# The ceiling is the other half: six points still have to be a session's opening, not
	# its whole arc.
	var sixth_point := LevelUpManager.xp_for_level(7)

	var err: String = _T.assert_true(
		sixth_point >= 90,
		"six skill points cost %d XP, which is the pacing gather-1n2 was filed about" % sixth_point
	)
	if err != "":
		return err

	return _T.assert_true(
		sixth_point <= 160,
		"six skill points cost %d XP, so the early tree is out of reach" % sixth_point
	)
