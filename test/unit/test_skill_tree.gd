extends RefCounted

## Guards the skill tree's shape and the stat plumbing behind it. The tree is
## hand-authored data, so these are mostly integrity checks: a typo in a
## prerequisite id or a stat name would otherwise fail silently at runtime and
## just leave a node permanently unbuyable or a passive doing nothing.

var _T

var tree: SkillTree
var items: Items
var resources: Resources
var recipes

## Every branch is a straight chain of at least this many tiers.
##
## It was an exact count until Industry grew a fifth rung for the mint (`gather-7p4`). A
## minimum rather than an equality because the raggedness is the deliberate part: the ore
## ladder is the game's spine and is allowed to run one card longer than its neighbours,
## while a branch coming up SHORT is still the bug this was written for — a column with a
## missing tier is a dead end the panel draws as if it were finished.
const MIN_TIERS := 4

## The one branch allowed past MIN_TIERS today, and how far. Stated rather than left open
## so that a second branch quietly growing a fifth tier — which would make the panel a wall
## of ragged columns rather than one deliberate exception — fails here.
const DEEPER_BRANCHES := {SkillTree.INDUSTRY: 5}

## Prerequisites normally run straight up a column. This is every skill allowed to name one
## from another branch, mapped to the requirement it is allowed to name.
##
## An allow-list rather than dropping the check, because the check is load-bearing: the
## panel draws connectors down a column only, so a cross-branch prerequisite is INVISIBLE
## on the tree and is discoverable solely through the detail pane's "requires" line. That
## is an acceptable price for one deliberate gate and a bad default for the tree at large.
const CROSS_BRANCH_REQUIREMENTS := {"gold_rush": "light_step"}


func setup() -> void:
	tree = SkillTree.new()

	# Autoloads are not available under the headless SceneTree runner, so the
	# registries are built directly the way test_progression does it.
	items = Items.new()
	items._ready()

	resources = Resources.new()
	resources.items = items
	resources._ready()

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
	# A cross-branch prerequisite draws no connector at all, and a downward one would draw
	# a line between two cards that are not vertically adjacent. Both are panel bugs, so
	# the only cross-branch edges permitted are the ones named in CROSS_BRANCH_REQUIREMENTS.
	for id in tree.order:
		var skill: Skill = tree.get_skill(id)
		for requirement in skill.requires:
			var parent: Skill = tree.get_skill(requirement)

			if parent.branch != skill.branch:
				if CROSS_BRANCH_REQUIREMENTS.get(id) != requirement:
					return _T.assert_true(
						false, "'%s' requires '%s' from another branch" % [id, requirement]
					)
				# A cross-branch edge has no shared column, so "above" is meaningless for
				# it; what matters instead is that it cannot deadlock, which the acyclicity
				# test below covers.
				continue

			if parent.tier >= skill.tier:
				return _T.assert_true(false, "'%s' requires '%s' at the same or lower tier" % [id, requirement])

	return ""


func test_every_declared_cross_branch_gate_is_still_in_the_tree() -> String:
	# The other half of the allow-list. Without this, removing gold_rush's Building
	# prerequisite would leave a stale entry that silently keeps permitting something
	# nothing does any more — an allow-list that only ever grows stops being a guard.
	for id in CROSS_BRANCH_REQUIREMENTS:
		var skill: Skill = tree.get_skill(id)
		if skill == null:
			return _T.assert_true(false, "cross-branch allow-list names unknown skill '%s'" % id)

		if not skill.requires.has(CROSS_BRANCH_REQUIREMENTS[id]):
			return _T.assert_true(
				false,
				"'%s' no longer requires '%s' — drop it from CROSS_BRANCH_REQUIREMENTS"
					% [id, CROSS_BRANCH_REQUIREMENTS[id]]
			)

	return ""


func test_the_prerequisite_graph_is_acyclic_and_fully_reachable() -> String:
	# Cross-branch edges make the tree a DAG rather than four independent chains, so
	# "every node is eventually buyable" stops being obvious by inspection. A cycle here
	# would not crash anything — is_available simply returns false forever, leaving a card
	# permanently locked with its requirement showing as met on the neighbouring column.
	var taken := {}

	# Repeatedly take everything currently available. A tree with no cycle drains; one
	# with a cycle stalls with nodes left over.
	for _pass in tree.order.size():
		var progressed := false
		for id in tree.order:
			if tree.is_available(id, taken):
				taken[id] = true
				progressed = true
		if not progressed:
			break

	for id in tree.order:
		if not taken.has(id):
			return _T.assert_true(
				false, "'%s' can never be bought — its prerequisites cannot all be met" % id
			)

	return ""


func test_each_branch_has_one_skill_per_tier() -> String:
	for branch in SkillTree.BRANCHES:
		var seen := {}
		for skill in tree.branch_skills(branch):
			if seen.has(skill.tier):
				return _T.assert_true(false, "%s has two skills at tier %d" % [branch, skill.tier])
			seen[skill.tier] = true

	return ""


func test_every_branch_is_a_full_contiguous_chain() -> String:
	# The panel draws one card per tier and one connector between neighbours, so a
	# branch that is short a tier, or that skips from tier 1 to tier 3, either leaves
	# a ragged column or an unreachable node. Contiguity from 0 is also what makes
	# "each gated on the one above" expressible at all.
	for branch in SkillTree.BRANCHES:
		var branch_skills := tree.branch_skills(branch)
		var expected_tiers: int = DEEPER_BRANCHES.get(branch, MIN_TIERS)

		var err: String = _T.assert_eq(
			branch_skills.size(), expected_tiers,
			"%s has %d tiers" % [branch, expected_tiers]
		)
		if err != "":
			return err

		if branch_skills.size() < MIN_TIERS:
			return _T.assert_true(false, "%s is short of the %d-tier minimum" % [branch, MIN_TIERS])

		for i in branch_skills.size():
			var skill: Skill = branch_skills[i]

			if skill.tier != i:
				return _T.assert_true(false, "%s tier %d is numbered %d" % [branch, i, skill.tier])

			# Tier 0 is the free entry point. Everything below it hangs off the node
			# directly above — and may name at most one extra prerequisite, from another
			# branch, if CROSS_BRANCH_REQUIREMENTS permits it.
			if i == 0:
				if not skill.requires.is_empty():
					return _T.assert_true(false, "'%s' is a tier 0 node with prerequisites" % skill.id)
				continue

			var parent_id: String = branch_skills[i - 1].id
			if not skill.requires.has(parent_id):
				return _T.assert_true(
					false, "'%s' does not chain off '%s', the tier above it" % [skill.id, parent_id]
				)

			var allowed := 2 if CROSS_BRANCH_REQUIREMENTS.has(skill.id) else 1
			if skill.requires.size() > allowed:
				return _T.assert_true(
					false, "'%s' names %d prerequisites; at most %d are permitted"
						% [skill.id, skill.requires.size(), allowed]
				)

	return ""


func test_a_skill_costs_its_depth() -> String:
	# The pass that made depth the price (`gather-7p4`). Every tier-0 node must stay at one
	# point — that is what keeps the opening identical to the flat-cost tree it replaced —
	# and every rung below it must cost strictly more than the rung above.
	for branch in SkillTree.BRANCHES:
		var branch_skills := tree.branch_skills(branch)

		var err: String = _T.assert_eq(
			branch_skills[0].cost(), 1, "%s's entry node costs one point" % branch
		)
		if err != "":
			return err

		for i in range(1, branch_skills.size()):
			if branch_skills[i].cost() <= branch_skills[i - 1].cost():
				return _T.assert_true(
					false,
					"'%s' costs %d, no more than '%s' above it"
						% [branch_skills[i].id, branch_skills[i].cost(), branch_skills[i - 1].id]
				)

	return ""


func test_clearing_the_tree_costs_far_more_than_one_point_per_node() -> String:
	# The regression this whole pass exists to prevent. Every node cost exactly one point,
	# so the 16-node tree cost 16 levels and a capstone was priced like an opener.
	#
	# Asserted as a ratio rather than a total, so it says the thing that matters — depth is
	# priced — and keeps saying it if the tree grows another node.
	var nodes := tree.order.size()
	var total := tree.total_cost()

	return _T.assert_true(
		total >= nodes * 2,
		"the %d-node tree costs %d points, which is close to one per node again" % [nodes, total]
	)


func test_reaching_gold_costs_more_than_its_own_branch() -> String:
	# The gold rush, pinned. gold_rush was four one-point nodes deep in a single branch,
	# so the currency that buys land was four levels from a fresh start. cost_to_reach
	# walks the prerequisites transitively, so this fails both if the cross-branch gate is
	# removed and if skills go back to costing a flat point each.
	var gold := tree.cost_to_reach("gold_rush")
	var industry_only := 0
	for skill in tree.branch_skills(SkillTree.INDUSTRY):
		if skill.tier <= 3:
			industry_only += skill.cost()

	var err: String = _T.assert_gt(
		gold, industry_only,
		"reaching gold costs %d points, all of them inside Industry — the beeline still works" % gold
	)
	if err != "":
		return err

	# The mint is a further rung on top, so striking coins is dearer again than finding the
	# ore. Splitting them is the second half of the gate and this is what holds them apart.
	return _T.assert_gt(
		tree.cost_to_reach("minting"), gold,
		"minting costs no more to reach than the gold veins that feed it"
	)


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


func test_every_unlocked_resource_exists() -> String:
	# LevelUpManager passes these straight to ResourceManager2.add_resource, which
	# looks the type up in Resources and returns silently when it misses — so a typo
	# here would just quietly never spawn the ore the skill promised.
	for id in tree.order:
		for resource_type in tree.get_skill(id).resources:
			if not resources.resources.has(resource_type):
				return _T.assert_true(false, "skill '%s' unlocks a resource that is not registered" % id)

	return ""


func test_no_resource_is_unlocked_twice() -> String:
	# add_resource is idempotent, but two skills promising the same ore means one of
	# them is silently granting nothing.
	var seen := {}
	for id in tree.order:
		for resource_type in tree.get_skill(id).resources:
			if seen.has(resource_type):
				return _T.assert_true(false, "'%s' and '%s' both unlock the same resource" % [seen[resource_type], id])
			seen[resource_type] = id

	return ""


func test_no_recipe_is_unlocked_twice() -> String:
	# Recipes.add_recipe appends without checking, so a doubly-unlocked product shows
	# up twice in the crafting list.
	var seen := {}
	for id in tree.order:
		for unlock in tree.get_skill(id).recipes:
			var key := "%d@%d" % [unlock["product"], unlock["station"]]
			if seen.has(key):
				return _T.assert_true(false, "'%s' and '%s' both unlock the same recipe" % [seen[key], id])
			seen[key] = id

	return ""


func test_the_legacy_iron_age_id_still_resolves() -> String:
	# LevelUpManager.LEGACY_IDS maps the pre-tree "iron" upgrade onto this id, and
	# every save written since stores it verbatim. Its content has been repointed at
	# copper, but the id itself must never be renamed.
	var err: String = _T.assert_true(tree.has_skill("iron_age"), "the iron_age id survives")
	if err != "":
		return err

	return _T.assert_true(
		tree.has_skill(LevelUpManager.LEGACY_IDS["iron"]),
		"every legacy id maps onto a real skill"
	)


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
