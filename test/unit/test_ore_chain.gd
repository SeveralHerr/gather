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

## resource node -> the ore it drops -> the bar that ore smelts into. Copper is
## deliberately toolless: there is no Types.Item entry for a copper pickaxe, so the
## copper bar earns its place as an ingredient instead (see the bar-sink test below).
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


func test_rarer_ore_nodes_pay_more_and_spawn_less() -> String:
	var iron := resources.Get(Types.Item.IronResource)
	var copper := resources.Get(Types.Item.CopperResource)
	var gold := resources.Get(Types.Item.GoldResource)

	var err: String = _T.assert_gt(copper.xp, iron.xp, "copper pays more xp than iron")
	if err != "":
		return err

	err = _T.assert_gt(gold.xp, copper.xp, "gold pays more xp than copper")
	if err != "":
		return err

	err = _T.assert_gt(iron.spawn_weight, copper.spawn_weight, "copper is rarer than iron")
	if err != "":
		return err

	return _T.assert_gt(copper.spawn_weight, gold.spawn_weight, "gold is rarer than copper")


func test_gold_is_the_node_that_pays_currency() -> String:
	# Coins are what land costs, so exactly one node needs to drop them or the
	# purchase loop has no source.
	var gold := resources.Get(Types.Item.GoldResource)

	var err: String = _T.assert_eq(gold.secondary_drop, Types.Item.Coin, "gold drops coins")
	if err != "":
		return err

	return _T.assert_gt(gold.secondary_drop_chance, 0.0, "and does so at a real rate")
