extends RefCounted

## Guards the early-game progression curve. These are the invariants that make the
## wood -> bone -> iron ladder read as progress: each tier must be strictly better,
## rarer nodes must pay more XP and spawn less, and a tier's recipe must cost the
## material that tier unlocked.

var _T

var items: Items
var resources: Resources
var recipes


func setup() -> void:
	# Items and Resources are autoloads/scene nodes in game, but they populate their
	# dictionaries in _ready(), which is callable directly off a bare instance here.
	items = Items.new()
	items._ready()

	resources = Resources.new()
	resources.items = items
	resources._ready()

	recipes = load("res://crafting/recipes.gd").new()
	recipes.furnace_recipes()
	recipes.sawmill_recipes()


func _pickaxe(type: Types.Item) -> GameItemPickaxe:
	return items.get_item(type) as GameItemPickaxe


func test_each_pickaxe_tier_gathers_faster() -> String:
	var wood := _pickaxe(Types.Item.WoodPickaxe)
	var bone := _pickaxe(Types.Item.BonePickaxe)
	var iron := _pickaxe(Types.Item.IronPickaxe)

	var err: String = _T.assert_gt(wood.power, bone.power, "bone gathers faster than wood")
	if err != "":
		return err

	return _T.assert_gt(bone.power, iron.power, "iron gathers faster than bone")


func test_each_pickaxe_tier_yields_more() -> String:
	var wood := _pickaxe(Types.Item.WoodPickaxe)
	var bone := _pickaxe(Types.Item.BonePickaxe)
	var iron := _pickaxe(Types.Item.IronPickaxe)

	var err: String = _T.assert_gt(bone.bonus_yield_chance, wood.bonus_yield_chance, "bone out-yields wood")
	if err != "":
		return err

	return _T.assert_gt(iron.bonus_yield_chance, bone.bonus_yield_chance, "iron out-yields bone")


func test_no_pickaxe_has_a_zero_gather_time() -> String:
	# A zero would be handed straight to a Timer's wait_time and error out.
	for type in [Types.Item.WoodPickaxe, Types.Item.BonePickaxe, Types.Item.IronPickaxe]:
		if _pickaxe(type).power <= 0.0:
			return _T.assert_true(false, "%s has a non-positive gather time" % _pickaxe(type).name)

	return ""


func test_iron_pickaxe_costs_iron_rather_than_bone() -> String:
	var recipe = recipes.get_sawmill_recipe(Types.Item.IronPickaxe)
	if recipe == null:
		return _T.assert_true(false, "no sawmill recipe for the iron pickaxe")

	var err: String = _T.assert_true(recipe.cost_list.has(Types.Item.IronBar), "iron pickaxe costs iron bars")
	if err != "":
		return err

	return _T.assert_false(recipe.cost_list.has(Types.Item.Bone), "iron pickaxe no longer costs bone")


func test_rarer_resources_award_more_xp() -> String:
	var tree := resources.Get(Types.Item.Tree)
	var coal := resources.Get(Types.Item.CoalResource)
	var iron := resources.Get(Types.Item.IronResource)

	var err: String = _T.assert_gt(coal.xp, tree.xp, "coal is worth more xp than a tree")
	if err != "":
		return err

	return _T.assert_gt(iron.xp, tree.xp, "iron is worth more xp than a tree")


func test_rarer_resources_spawn_less_often() -> String:
	var tree := resources.Get(Types.Item.Tree)
	var coal := resources.Get(Types.Item.CoalResource)
	var iron := resources.Get(Types.Item.IronResource)

	var err: String = _T.assert_gt(tree.spawn_weight, coal.spawn_weight, "trees are commoner than coal")
	if err != "":
		return err

	return _T.assert_gt(tree.spawn_weight, iron.spawn_weight, "trees are commoner than iron")


func test_every_resource_is_tuned() -> String:
	# A resource missing from the tuning table silently falls back to weight 1 / xp 1,
	# which would quietly flatten the curve rather than failing loudly.
	for key in resources.GetAllTypes():
		if not Resources.TUNING.has(key):
			return _T.assert_true(false, "resource %s has no tuning entry" % resources.Get(key).name)

	return ""


func test_food_actually_heals() -> String:
	var food = items.get_item(Types.Item.Food)

	var err: String = _T.assert_true(food is GameItemConsumable, "food is a consumable")
	if err != "":
		return err

	return _T.assert_gt(food.heal_value, 0, "food has a real heal value")


func test_trees_are_a_food_source() -> String:
	var tree := resources.Get(Types.Item.Tree)

	var err: String = _T.assert_eq(tree.secondary_drop, Types.Item.Food, "trees drop food as a secondary")
	if err != "":
		return err

	return _T.assert_gt(tree.secondary_drop_chance, 0.0, "the food drop chance is nonzero")
