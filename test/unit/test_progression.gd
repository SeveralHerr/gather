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
	recipes.workbench_recipes()


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
	var recipe = recipes.get_workbench_recipe(Types.Item.IronPickaxe)
	if recipe == null:
		return _T.assert_true(false, "no workbench recipe for the iron pickaxe")

	var err: String = _T.assert_true(recipe.cost_list.has(Types.Item.IronBar), "iron pickaxe costs iron bars")
	if err != "":
		return err

	return _T.assert_false(recipe.cost_list.has(Types.Item.Bone), "iron pickaxe no longer costs bone")


func test_every_resource_awards_the_same_xp() -> String:
	# Rarity is no longer priced in xp. It was (tree 1, coal 3, iron 4, up to gold 9),
	# and that made the mining tier the fastest route through the skill tree instead of
	# the slow route to materials. Rarity is now spawn_weight and drop value only, so
	# this asserts the flat award rather than the old ladder.
	var tree := resources.Get(Types.Item.Tree)
	var coal := resources.Get(Types.Item.CoalResource)
	var iron := resources.Get(Types.Item.IronResource)

	var err: String = _T.assert_eq(coal.xp, tree.xp, "coal is worth the same xp as a tree")
	if err != "":
		return err

	return _T.assert_eq(iron.xp, tree.xp, "iron is worth the same xp as a tree")


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


## The inverse of the test this replaces, and the reason it is stated as a test rather than
## just deleted: "trees drop food" was true for the whole life of the project, so the thing
## worth pinning is that it is deliberately no longer true. Food is a 4% enemy drop now
## (EnemyRegistry.FOOD_DROP) and the berry bush is the forager's heal.
func test_trees_no_longer_hand_out_food() -> String:
	var tree := resources.Get(Types.Item.Tree)

	return _T.assert_true(
		tree.secondary_drop_chance <= 0.0 or tree.secondary_drop != Types.Item.Food,
		"trees no longer drop Food; it is an enemy drop"
	)


func test_food_is_a_rare_drop_off_every_enemy() -> String:
	for type in [EnemyRegistry.BONE, EnemyRegistry.SPIDER, EnemyRegistry.ELITE]:
		var chance := 0.0
		for entry in EnemyRegistry.loot_table(type):
			if entry.get("item") == Types.Item.Food:
				chance = float(entry.get("chance", 0.0))

		var err: String = _T.assert_gt(chance, 0.0, "%s can drop Food" % type)
		if err != "":
			return err

		# Rare, and stated as an upper bound: the point of the change is that a full heal is
		# not something the player trips over, so a later edit that quietly walks this back
		# towards the tree's old 0.2 should fail here.
		err = _T.assert_true(chance <= 0.1, "%s drops Food rarely (%.2f)" % [type, chance])
		if err != "":
			return err

	return ""


func test_a_berry_is_the_smallest_heal_in_the_game() -> String:
	var berry = items.get_item(Types.Item.Berry)

	var err: String = _T.assert_true(berry is GameItemConsumable, "a berry is a consumable")
	if err != "":
		return err

	err = _T.assert_gt(berry.heal_value, 0, "a berry actually heals")
	if err != "":
		return err

	# Against Food rather than against a literal: the relationship is what matters. A berry
	# is the nibble you pick constantly; Food is the emergency you fought something for.
	var food = items.get_item(Types.Item.Food)
	return _T.assert_gt(food.heal_value, berry.heal_value, "Food heals more than a berry")


func test_the_berry_bush_is_available_from_the_first_frame() -> String:
	# Food no longer falls off trees, so a player who has not fought anything has no other
	# way to heal. A bush behind a skill would mean a starting island with no heal at all.
	return _T.assert_true(
		ResourceManager2.STARTING_RESOURCES.has(Types.Item.BerryBush),
		"the berry bush is unlocked from the start"
	)
