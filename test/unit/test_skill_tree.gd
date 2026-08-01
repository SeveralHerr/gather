extends RefCounted

## Guards the skill tree's shape and the stat plumbing behind it. The tree is
## hand-authored data, so these are mostly integrity checks: a typo in a
## prerequisite id or a stat name would otherwise fail silently at runtime and
## just leave a node permanently unbuyable or a passive doing nothing.

var _T

var tree: SkillTree
var items: Items
var recipes


func setup() -> void:
	tree = SkillTree.new()

	# Autoloads are not available under the headless SceneTree runner, so the
	# registries are built directly the way test_progression does it.
	items = Items.new()
	items._ready()

	recipes = load("res://crafting/recipes.gd").new()
	recipes.furnace_recipes()
	recipes.sawmill_recipes()


func test_every_prerequisite_names_a_real_skill() -> String:
	for id in tree.order:
		for requirement in tree.get_skill(id).requires:
			if not tree.has_skill(requirement):
				return _T.assert_true(false, "skill '%s' requires unknown '%s'" % [id, requirement])

	return ""


func test_prerequisites_stay_inside_their_own_branch_and_above() -> String:
	# A cross-branch or downward prerequisite would draw a connector line between
	# two cards that are not actually vertically adjacent in the panel.
	for id in tree.order:
		var skill: Skill = tree.get_skill(id)
		for requirement in skill.requires:
			var parent: Skill = tree.get_skill(requirement)
			if parent.branch != skill.branch:
				return _T.assert_true(false, "'%s' requires '%s' from another branch" % [id, requirement])
			if parent.tier >= skill.tier:
				return _T.assert_true(false, "'%s' requires '%s' at the same or lower tier" % [id, requirement])

	return ""


func test_each_branch_has_one_skill_per_tier() -> String:
	for branch in SkillTree.BRANCHES:
		var seen := {}
		for skill in tree.branch_skills(branch):
			if seen.has(skill.tier):
				return _T.assert_true(false, "%s has two skills at tier %d" % [branch, skill.tier])
			seen[skill.tier] = true

	return ""


func test_every_branch_has_a_free_entry_point() -> String:
	# Without one, a branch can never be started and its whole column is dead.
	for branch in SkillTree.BRANCHES:
		var has_entry := false
		for skill in tree.branch_skills(branch):
			if skill.requires.is_empty():
				has_entry = true

		if not has_entry:
			return _T.assert_true(false, "%s has no skill available from the start" % branch)

	return ""


func test_every_branch_is_coloured_and_described() -> String:
	for branch in SkillTree.BRANCHES:
		if not SkillTree.BRANCH_COLORS.has(branch):
			return _T.assert_true(false, "branch %s has no colour" % branch)
		if not SkillTree.BRANCH_TAGLINES.has(branch):
			return _T.assert_true(false, "branch %s has no tagline" % branch)

	return ""


func test_every_effect_targets_a_real_stat() -> String:
	for id in tree.order:
		for stat in tree.get_skill(id).effects:
			if not PlayerStats.BASE.has(stat):
				return _T.assert_true(false, "skill '%s' targets unknown stat '%s'" % [id, stat])

	return ""


func test_every_unlocked_recipe_exists() -> String:
	for id in tree.order:
		for unlock in tree.get_skill(id).recipes:
			var recipe
			if unlock["station"] == Types.Item.Furnace:
				recipe = recipes.get_furnace_recipe(unlock["product"])
			else:
				recipe = recipes.get_sawmill_recipe(unlock["product"])

			if recipe == null:
				return _T.assert_true(false, "skill '%s' unlocks a recipe that does not exist" % id)

	return ""


func test_every_skill_has_an_icon_item() -> String:
	for id in tree.order:
		if items.get_item(tree.get_skill(id).icon) == null:
			return _T.assert_true(false, "skill '%s' has no icon item" % id)

	return ""


func test_every_skill_is_described() -> String:
	for id in tree.order:
		var skill: Skill = tree.get_skill(id)
		if skill.display_name == "" or skill.description == "" or skill.summary == "":
			return _T.assert_true(false, "skill '%s' is missing display text" % id)
		# Longer summaries wrap and blow out the four-column layout.
		if skill.summary.length() > 22:
			return _T.assert_true(false, "skill '%s' has an over-long card summary" % id)

	return ""


func test_a_skill_unlocks_only_once_its_prerequisite_is_taken() -> String:
	var taken := {}

	var err: String = _T.assert_true(tree.is_available("swift_hands", taken), "the entry node starts available")
	if err != "":
		return err

	err = _T.assert_false(tree.is_available("bountiful", taken), "the tier 2 node starts locked")
	if err != "":
		return err

	taken["swift_hands"] = true
	err = _T.assert_true(tree.is_available("bountiful", taken), "taking tier 1 unlocks tier 2")
	if err != "":
		return err

	return _T.assert_false(tree.is_available("swift_hands", taken), "a taken node is no longer available")


func test_missing_requirements_names_what_is_missing() -> String:
	var missing := tree.missing_requirements("bountiful", {})

	var err: String = _T.assert_eq(missing.size(), 1, "one missing prerequisite")
	if err != "":
		return err

	return _T.assert_eq(missing[0], "Swift Hands", "reported by display name")


func test_has_any_available_goes_false_only_when_the_tree_is_finished() -> String:
	var taken := {}
	var err: String = _T.assert_true(tree.has_any_available(taken), "a fresh tree has something to buy")
	if err != "":
		return err

	for id in tree.order:
		taken[id] = true

	return _T.assert_false(tree.has_any_available(taken), "a fully taken tree has nothing left")
