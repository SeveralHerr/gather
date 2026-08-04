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


func test_no_level_is_cheaper_than_the_one_before_it() -> String:
	# The bug the whole curve reshape was for, and the one thing test_the_xp_curve_climbs above
	# could never catch: it checks that the CUMULATIVE threshold climbs, which it does under any
	# curve that charges anything at all, so it passed happily while a level cost a fifth of the
	# level before it.
	#
	# XP_GROWTH used to compound the cumulative total, making one level's cost 19% of everything
	# earned so far — 40 XP for level 2, then 8, 10, 12, 14, 16. What a player feels is the step,
	# not the sum, and a step that collapses immediately after the first level reads as
	# "levelling stopped costing anything", which is exactly what was reported. Twice.
	var previous := 0
	for target_level in range(2, 50):
		var step := LevelUpManager.cost_of_level(target_level)

		var err: String = _T.assert_gte(
			step, previous,
			"level %d costs %d XP where level %d cost %d — the curve dips" % [
				target_level, step, target_level - 1, previous]
		)
		if err != "":
			return err

		err = _T.assert_gte(
			step, LevelUpManager.XP_FIRST_LEVEL,
			"level %d costs %d XP, less than the %d the first level cost" % [
				target_level, step, LevelUpManager.XP_FIRST_LEVEL]
		)
		if err != "":
			return err

		previous = step

	return ""


func test_the_step_is_what_the_threshold_is_made_of() -> String:
	# cost_of_level and xp_for_level are two readings of one curve, and the game reads both:
	# add_xp advances `next_level` with the second while a player experiences the first. They
	# drifted apart before — xp_for_level compounded a total that no per-level cost matched —
	# so this pins them to each other rather than to a number.
	var running := 0
	for target_level in range(2, 30):
		running += LevelUpManager.cost_of_level(target_level)

		var err: String = _T.assert_eq(
			LevelUpManager.xp_for_level(target_level), running,
			"level %d's threshold is not the sum of every level's cost up to it" % target_level
		)
		if err != "":
			return err

	return _T.assert_eq(LevelUpManager.xp_for_level(1), 0, "a fresh player has earned nothing")


func test_the_whole_tree_is_a_campaign_not_a_session() -> String:
	# This was test_the_whole_tree_is_reachable_in_one_run, and its premise was one point
	# per level: clearing every node meant reaching level (nodes + 1), sixteen levels, 578
	# XP. Skills cost tier+1 points now (`gather-7p4`), so the tree is 45 points and 45
	# levels — the test is not measuring the same thing any more and its 650 bound cannot
	# simply be nudged.
	#
	# The intent it guarded is still real and still worth a bound, so it is restated
	# rather than dropped: the tree must remain FINISHABLE. The failure mode it was
	# written against — a curve that outruns the 1 XP a node pays and leaves the capstones
	# as decoration — is what compounding does over 45 levels with nothing to stop it
	# (15,358 XP at the current rate, 90,053 at the 1.19 this was written against), so this
	# is the test that fails if XP_STEP_CAP is ever removed.
	#
	# The band, not a point: 10,000 is roughly a long campaign at a node a second, and the
	# floor is what stops a future pass "fixing" the tail by flattening the curve into
	# something cheaper than the tree it replaced.
	var points_needed := tree.total_cost()
	var xp_needed := LevelUpManager.xp_for_level(points_needed + 1)

	var err: String = _T.assert_true(
		xp_needed < 10000,
		"clearing the %d-point tree costs %d XP, which is out of reach at 1 XP a node"
			% [points_needed, xp_needed]
	)
	if err != "":
		return err

	return _T.assert_true(
		xp_needed > 1500,
		"clearing the tree costs only %d XP — the depth pricing is not reaching the curve"
			% xp_needed
	)


func test_a_single_branch_is_reachable_in_one_run() -> String:
	# What "one run" means now that the whole tree is not one. A player who commits to a
	# single branch should see its capstone inside a session — that is what makes choosing
	# a branch a strategy rather than a thing that pays off two sessions later.
	#
	# Foraging is the cheapest full branch (1+2+3+4 = 10 points) and the one a new player
	# is most likely to push, so it is the honest floor to measure.
	var branch_cost := 0
	for skill in tree.branch_skills(SkillTree.FORAGING):
		branch_cost += skill.cost()

	var xp_needed := LevelUpManager.xp_for_level(branch_cost + 1)

	# 400 was this bound until the curve was reshaped, and it was not a design figure: with the
	# cost of a level pinned to 19% of the running total, levels 3 to 11 cost 8 to 33 XP, and
	# nine levels for the price of five nodes each is what "a session" then meant. The bound is
	# arithmetically impossible now and rightly so — ten levels that never cost less than the
	# first cannot come to less than ten times the first, i.e. 400 on the nose.
	#
	# 800 restates the intent against a monotone curve: a player who commits to one branch sees
	# its capstone inside a session. It currently lands at 574, so there is room for the growth
	# rate to move without this bound moving with it.
	return _T.assert_true(
		xp_needed < 800,
		"a full Foraging branch costs %d XP, which is more than a session" % xp_needed
	)


func test_the_curve_stops_compounding_before_it_runs_away() -> String:
	# XP_STEP_CAP directly. Without it the curve is geometric for all 45 levels and the
	# last one alone costs more than every level before it put together, which is the
	# shape that made the tree unfinishable.
	var previous := LevelUpManager.XP_FIRST_LEVEL
	var largest_step := 0
	for target_level in range(3, 50):
		var threshold := LevelUpManager.xp_for_level(target_level)
		largest_step = maxi(largest_step, threshold - previous)
		previous = threshold

	return _T.assert_true(
		largest_step <= LevelUpManager.XP_STEP_CAP,
		"a level costs %d more than the one before it, past the %d cap"
			% [largest_step, LevelUpManager.XP_STEP_CAP]
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
	#
	# "A third of the tree" was the 2026-era reading and no longer holds: tiered costs
	# (`gather-7p4`) make six points 13% of a 45-point tree, and they buy four skills
	# rather than six. The XP figure is unmoved — the cap only bites past level 19 — so
	# this test is measuring the same curve, just a smaller slice of tree.
	var sixth_point := LevelUpManager.xp_for_level(7)

	var err: String = _T.assert_true(
		sixth_point >= 90,
		"six skill points cost %d XP, which is the pacing gather-1n2 was filed about" % sixth_point
	)
	if err != "":
		return err

	# 160 was the ceiling while a level cost 19% of the running total, so the five levels after
	# the first came to 60 XP between them and 160 was generous. It now costs 291: the levels
	# after the first stopped being nearly free, which is the fix, and a ceiling calibrated on
	# the broken shape would veto it.
	#
	# 450 is the same statement about pacing, measured against a curve where no level is cheaper
	# than the first: six levels for 450 XP is an average of 75, under twice the opening level's
	# price, so the first four skills are still an opening and not the whole arc. The floor above
	# is what guards the reported symptom; this half only stops the opening becoming a grind.
	return _T.assert_true(
		sixth_point <= 450,
		"six skill points cost %d XP, so the early tree is out of reach" % sixth_point
	)
