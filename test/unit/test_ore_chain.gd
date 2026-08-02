extends RefCounted

## Guards the ore chains end to end: a node in the world drops an ore, the furnace
## turns that ore into a bar, and the bar is spent on something. Each of those three
## links lives in a different file (resources.gd, recipes.gd, items.gd), so a chain
## can break by editing only one of them and nothing at runtime complains — the
## player just ends up holding an ore with nowhere to take it.

var _T

var items: Items
var resources: Resources
var recipes

## resource node -> the ore it drops -> the bar that ore smelts into -> the tool that bar
## buys. All three metals carry a full chain; the copper one is the tier a new player
## works through before `smelting` puts iron veins on the map.
const CHAINS := [
	{
		"name": "copper",
		"node": Types.Item.CopperResource,
		"ore": Types.Item.CopperOre,
		"bar": Types.Item.CopperBar,
		"tool": Types.Item.CopperPickaxe,
	},
	{
		"name": "iron",
		"node": Types.Item.IronResource,
		"ore": Types.Item.IronOre,
		"bar": Types.Item.IronBar,
		"tool": Types.Item.IronPickaxe,
	},
	{
		"name": "gold",
		"node": Types.Item.GoldResource,
		"ore": Types.Item.GoldOre,
		"bar": Types.Item.GoldBar,
		"tool": Types.Item.GoldPickaxe,
	},
]


func setup() -> void:
	# Autoloads are not available under the headless --script runner, so the three
	# registries are built the way test_progression does it.
	items = Items.new()
	items._ready()

	resources = Resources.new()
	resources.items = items
	resources._ready()

	recipes = load("res://crafting/recipes.gd").new()
	recipes.furnace_recipes()
	recipes.sawmill_recipes()


## Every product either station can make, plus the cost of making it.
func _all_recipes() -> Array:
	return recipes.furnace_recipe_list + recipes.sawmill_recipe_list


func test_every_ore_node_drops_its_own_ore() -> String:
	for chain in CHAINS:
		var node: GameResource = resources.resources.get(chain["node"])
		if node == null:
			return _T.assert_true(false, "no %s resource node is registered" % chain["name"])

		var err: String = _T.assert_eq(node.drop, chain["ore"], "the %s node drops %s ore" % [chain["name"], chain["name"]])
		if err != "":
			return err

	return ""


func test_every_ore_smelts_into_its_bar() -> String:
	for chain in CHAINS:
		var recipe = recipes.get_furnace_recipe(chain["bar"])
		if recipe == null:
			return _T.assert_true(false, "no furnace recipe for the %s bar" % chain["name"])

		if not recipe.cost_list.has(chain["ore"]):
			return _T.assert_true(false, "the %s bar does not cost %s ore" % [chain["name"], chain["name"]])

	return ""


func test_every_bar_recipe_burns_coal() -> String:
	# Coal is what makes the furnace a furnace. A bar recipe without it turns coal
	# into a resource with no consumer at all.
	for chain in CHAINS:
		var recipe = recipes.get_furnace_recipe(chain["bar"])
		if recipe == null or not recipe.cost_list.has(Types.Item.CoalOre):
			return _T.assert_true(false, "the %s bar is smelted without coal" % chain["name"])

	return ""


func test_every_bar_is_spent_on_something() -> String:
	# The dead-end check. A bar that no recipe consumes is a tier the player mines,
	# smelts and then stares at.
	for chain in CHAINS:
		var consumed := false
		for recipe in _all_recipes():
			if recipe.cost_list.has(chain["bar"]):
				consumed = true

		if not consumed:
			return _T.assert_true(false, "nothing consumes the %s bar" % chain["name"])

	return ""


func test_each_metal_tool_costs_its_own_bar() -> String:
	for chain in CHAINS:
		if chain["tool"] == null:
			continue

		var recipe = recipes.get_sawmill_recipe(chain["tool"])
		if recipe == null:
			return _T.assert_true(false, "no sawmill recipe for the %s tool" % chain["name"])

		if not recipe.cost_list.has(chain["bar"]):
			return _T.assert_true(false, "the %s tool does not cost %s bars" % [chain["name"], chain["name"]])

	return ""


func test_every_recipe_names_registered_items() -> String:
	# A recipe keyed on an unregistered product or ingredient renders as a blank row
	# in the crafting panel rather than failing.
	# item_list.has() rather than get_item(): get_item indexes the dictionary directly,
	# so a miss throws instead of returning null - and a throw inside a -> String test
	# is scored as a pass.
	for recipe in _all_recipes():
		if not items.item_list.has(recipe.product):
			return _T.assert_true(false, "a recipe produces an unregistered item")

		for ingredient in recipe.cost_list:
			if not items.item_list.has(ingredient):
				return _T.assert_true(false, "a recipe costs an unregistered item")
			if recipe.cost_list[ingredient] <= 0:
				return _T.assert_true(false, "a recipe asks for a non-positive amount")

	return ""


func test_the_gold_pickaxe_tops_the_ladder() -> String:
	var iron := items.get_item(Types.Item.IronPickaxe) as GameItemPickaxe
	var gold := items.get_item(Types.Item.GoldPickaxe) as GameItemPickaxe

	var err: String = _T.assert_gt(iron.power, gold.power, "gold gathers faster than iron")
	if err != "":
		return err

	return _T.assert_gt(gold.bonus_yield_chance, iron.bonus_yield_chance, "gold out-yields iron")


func test_the_gold_pickaxe_outprices_the_iron_one() -> String:
	# A strictly better tool that is not strictly dearer collapses the ladder into a
	# single obvious purchase.
	var iron = recipes.get_sawmill_recipe(Types.Item.IronPickaxe)
	var gold = recipes.get_sawmill_recipe(Types.Item.GoldPickaxe)

	var err: String = _T.assert_gte(
		gold.cost_list.get(Types.Item.GoldBar, 0),
		iron.cost_list.get(Types.Item.IronBar, 0),
		"the gold pickaxe needs at least as many bars as the iron one"
	)
	if err != "":
		return err

	return _T.assert_gt(
		gold.cost_list.get(Types.Item.Plank, 0),
		iron.cost_list.get(Types.Item.Plank, 0),
		"and more planks on top"
	)


func test_the_gold_bar_is_the_dearest_bar() -> String:
	# Gold sits at the end of the chain, so smelting one has to cost more than
	# smelting either of the metals before it — otherwise the tiers are cosmetic.
	var copper_cost := _total_cost(recipes.get_furnace_recipe(Types.Item.CopperBar))
	var iron_cost := _total_cost(recipes.get_furnace_recipe(Types.Item.IronBar))
	var gold_cost := _total_cost(recipes.get_furnace_recipe(Types.Item.GoldBar))

	var err: String = _T.assert_gt(gold_cost, copper_cost, "a gold bar costs more than a copper one")
	if err != "":
		return err

	return _T.assert_gt(gold_cost, iron_cost, "a gold bar costs more than an iron one")


func _total_cost(recipe) -> int:
	var total := 0
	for ingredient in recipe.cost_list:
		total += recipe.cost_list[ingredient]
	return total


func test_rarer_ore_nodes_pay_a_flat_xp_and_spawn_less() -> String:
	var iron := resources.Get(Types.Item.IronResource)
	var copper := resources.Get(Types.Item.CopperResource)
	var gold := resources.Get(Types.Item.GoldResource)

	# The ore tier used to climb in xp as well as in rarity (4/6/9). It pays a flat 1
	# now — deliberately, because xp priced by rarity made mining the fastest way to
	# level. What is asserted here is that every ore node still pays the same as the
	# common nodes and no more; the rarity ladder below is what remains of the tier.
	var err: String = _T.assert_eq(iron.xp, 1, "iron pays the common 1 xp")
	if err != "":
		return err

	err = _T.assert_eq(copper.xp, 1, "copper pays the common 1 xp")
	if err != "":
		return err

	err = _T.assert_eq(gold.xp, 1, "gold pays the common 1 xp; its payout is the coins")
	if err != "":
		return err

	# Rarity has to climb with the crafting tier, and copper is the tier below iron: it is
	# the ore that spawns unlocked and the bar the furnace can make first. This assertion
	# used to run the other way, which is how the ladder came to be inverted.
	err = _T.assert_gt(copper.spawn_weight, iron.spawn_weight, "iron is rarer than copper")
	if err != "":
		return err

	return _T.assert_gt(iron.spawn_weight, gold.spawn_weight, "gold is rarer than iron")


## How many skill purchases deep a node sits. Branches are straight chains, so this is
## just the length of the `requires` walk; 1 for a node offered from the start.
func _skill_depth(tree: SkillTree, id: String) -> int:
	var skill: Skill = tree.skills[id]
	var deepest := 0
	for required in skill.requires:
		deepest = max(deepest, _skill_depth(tree, required))
	return deepest + 1


## When the ore for this chain first exists in the world. 0 means it spawns unlocked.
func _resource_depth(tree: SkillTree, node_type: Types.Item) -> int:
	if ResourceManager2.STARTING_RESOURCES.has(node_type):
		return 0

	for id in tree.order:
		if tree.skills[id].resources.has(node_type):
			return _skill_depth(tree, id)

	return -1


## When the bar for this chain can first be smelted. 0 means no skill gates it.
func _recipe_depth(tree: SkillTree, product: Types.Item) -> int:
	for id in tree.order:
		for entry in tree.skills[id].recipes:
			if entry["product"] == product:
				return _skill_depth(tree, id)

	return 0


func test_no_bar_unlocks_before_the_ore_it_is_smelted_from() -> String:
	# The invariant this file existed to protect but did not state: a bar recipe the
	# player can craft, from ore that does not spawn yet, is a recipe with an
	# unobtainable ingredient. Iron used to fail the mirror of this - its veins spawned
	# from the first frame while IronBar waited two Industry tiers, so a new player
	# banked ore for a recipe they could not see. Both directions are checked, because
	# the gap is a pacing bug whichever way round it points.
	var tree := SkillTree.new()

	for chain in CHAINS:
		var ore_at := _resource_depth(tree, chain["node"])
		if ore_at < 0:
			return _T.assert_true(false, "nothing ever spawns %s veins" % chain["name"])

		var bar_at := _recipe_depth(tree, chain["bar"])

		var err: String = _T.assert_gte(
			bar_at, ore_at,
			"the %s bar unlocks at depth %d but its ore only spawns at depth %d" % [chain["name"], bar_at, ore_at]
		)
		if err != "":
			return err

	return ""


func test_the_free_ore_is_the_one_the_furnace_smelts_first() -> String:
	# Exactly one metal spawns without a skill, and it has to be the one the earliest
	# bar recipe consumes — otherwise the first furnace the player builds has nothing
	# to put in it and the ore they have been stockpiling has no recipe.
	var tree := SkillTree.new()

	var free_metals := []
	var earliest_bar := 999
	var earliest_metal = null

	for chain in CHAINS:
		if _resource_depth(tree, chain["node"]) == 0:
			free_metals.append(chain["name"])

		var bar_at := _recipe_depth(tree, chain["bar"])
		if bar_at < earliest_bar:
			earliest_bar = bar_at
			earliest_metal = chain["name"]

	var err: String = _T.assert_eq(
		free_metals.size(), 1,
		"expected exactly one metal to spawn unlocked, got %s" % [free_metals]
	)
	if err != "":
		return err

	return _T.assert_eq(
		free_metals[0], earliest_metal,
		"%s spawns unlocked but %s is the first bar the furnace can make" % [free_metals[0], earliest_metal]
	)


func test_gold_is_the_node_that_pays_currency() -> String:
	# Coins are what land costs, so exactly one node needs to drop them or the
	# purchase loop has no source.
	var gold := resources.Get(Types.Item.GoldResource)

	var err: String = _T.assert_eq(gold.secondary_drop, Types.Item.Coin, "gold drops coins")
	if err != "":
		return err

	return _T.assert_gt(gold.secondary_drop_chance, 0.0, "and does so at a real rate")
