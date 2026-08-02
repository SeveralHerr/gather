extends RefCounted

## Guards the paying half of crafting and the unlock registry behind it.
##
## Both were quietly broken for a long time in ways nothing at runtime complained
## about: the panel charged one of each ingredient no matter what the recipe said, and
## the plank recipe existed in the master list while no skill and no seed ever moved
## it into the unlocked one — which made three of the four pickaxes uncraftable on a
## clean save without a single error anywhere.

var _T

var items: Items
var recipes
var tree: SkillTree


func setup() -> void:
	# Autoloads are not available under the headless --script runner, so the
	# registries are built by hand the way test_ore_chain does it.
	items = Items.new()
	items._ready()

	recipes = load("res://crafting/recipes.gd").new()
	recipes.furnace_recipes()
	recipes.sawmill_recipes()
	recipes._seed_day_one()

	tree = SkillTree.new()


func _inventory_with(contents: Dictionary) -> InventoryData:
	var data := InventoryData.new()
	for type in contents:
		var slot := SlotData.new()
		slot.item = items.get_item(type)
		slot.count = contents[type]
		data.inventory_slot_datas.append(slot)
	return data


# --- paying for a recipe -----------------------------------------------------

func test_spending_charges_the_full_per_unit_cost() -> String:
	# The bug this replaces: one remove() per cost KEY, so a 5-bar recipe took 1 bar.
	var data := _inventory_with({Types.Item.IronBar: 10, Types.Item.Plank: 6})
	var recipe = recipes.get_sawmill_recipe(Types.Item.IronPickaxe)

	var paid: bool = data.spend_cost(recipe.cost_list, 1)
	var err: String = _T.assert_true(paid, "an affordable recipe is paid for")
	if err != "":
		return err

	err = _T.assert_eq(data.count_of_type(Types.Item.IronBar), 5, "5 of the 10 iron bars are gone")
	if err != "":
		return err
	return _T.assert_eq(data.count_of_type(Types.Item.Plank), 4, "2 of the 6 planks are gone")


func test_spending_multiplies_by_the_amount_crafted() -> String:
	var data := _inventory_with({Types.Item.Wood: 30})
	var recipe = recipes.get_sawmill_recipe(Types.Item.String)

	var paid: bool = data.spend_cost(recipe.cost_list, 4)
	var err: String = _T.assert_true(paid, "four twine is affordable out of 30 wood")
	if err != "":
		return err
	return _T.assert_eq(data.count_of_type(Types.Item.Wood), 18, "4 x 3 wood is charged, not 3")


func test_affording_counts_across_split_stacks() -> String:
	# has_items() stopped at the first matching slot, so a player holding the same
	# item in two stacks read as unable to afford what they were plainly carrying.
	var data := InventoryData.new()
	for i in 2:
		var slot := SlotData.new()
		slot.item = items.get_item(Types.Item.Stone)
		slot.count = 5
		data.inventory_slot_datas.append(slot)
	var wood := SlotData.new()
	wood.item = items.get_item(Types.Item.Wood)
	wood.count = 4
	data.inventory_slot_datas.append(wood)

	var recipe = recipes.get_sawmill_recipe(Types.Item.StonePickaxe)
	return _T.assert_true(
		data.can_afford(recipe.cost_list, 1),
		"8 stone spread over two stacks of 5 pays an 8-stone recipe")


func test_an_unaffordable_recipe_removes_nothing() -> String:
	# All-or-nothing matters because the old path had no craft-time check at all and
	# remove() silently no-ops on a miss, so a partial payment left no trace.
	var data := _inventory_with({Types.Item.Stone: 8, Types.Item.Wood: 1})
	var recipe = recipes.get_sawmill_recipe(Types.Item.StonePickaxe)

	var paid: bool = data.spend_cost(recipe.cost_list, 1)
	var err: String = _T.assert_false(paid, "one wood short is refused")
	if err != "":
		return err
	return _T.assert_eq(data.count_of_type(Types.Item.Stone), 8, "the stone is untouched")


func test_affordable_count_is_the_tightest_ingredient() -> String:
	var data := _inventory_with({Types.Item.Stone: 40, Types.Item.Wood: 5})
	var recipe = recipes.get_sawmill_recipe(Types.Item.StonePickaxe)
	# 40 stone is 5 pickaxes' worth, 5 wood is only 2.
	return _T.assert_eq(data.affordable_count(recipe.cost_list), 2, "wood is the binding constraint")


# --- the unlock registry -----------------------------------------------------

func test_every_recipe_is_reachable() -> String:
	# The test that would have caught the plank. A recipe nothing unlocks is dead
	# content, and worse when something else costs its product.
	var reachable := {}
	for entry in recipes.DAY_ONE_RECIPES:
		reachable["%d@%d" % [entry["product"], entry["station"]]] = true
	for id in tree.order:
		for unlock in tree.get_skill(id).recipes:
			reachable["%d@%d" % [unlock["product"], unlock["station"]]] = true

	for recipe in recipes.sawmill_recipe_list:
		if not reachable.has("%d@%d" % [recipe.product, Types.Item.Sawmill]):
			return _T.assert_true(false,
				"sawmill recipe '%s' is unlocked by nothing" % items.get_item(recipe.product).name)
	for recipe in recipes.furnace_recipe_list:
		if not reachable.has("%d@%d" % [recipe.product, Types.Item.Furnace]):
			return _T.assert_true(false,
				"furnace recipe '%s' is unlocked by nothing" % items.get_item(recipe.product).name)
	return ""


func test_the_plank_is_available_from_the_first_frame() -> String:
	# Three of the four pickaxes cost planks, so this one is load-bearing for the
	# whole Industry branch.
	return _T.assert_true(
		recipes.is_unlocked(Types.Item.Plank, Types.Item.Sawmill),
		"the plank recipe is seeded on a clean save")


func test_unlocking_the_same_recipe_twice_adds_one_entry() -> String:
	var before: int = recipes.get_recipes(Types.Item.Sawmill).size()
	recipes.add_recipe(Types.Item.Chest, Types.Item.Sawmill)
	return _T.assert_eq(recipes.get_recipes(Types.Item.Sawmill).size(), before,
		"re-unlocking an already-known recipe is a no-op")


func test_unlocking_an_unknown_product_appends_nothing() -> String:
	# add_recipe used to append whatever the lookup returned, including null, which
	# every consumer then dereferenced.
	var before: int = recipes.get_recipes(Types.Item.Furnace).size()
	recipes.add_recipe(Types.Item.Tree, Types.Item.Furnace)
	var err: String = _T.assert_eq(recipes.get_recipes(Types.Item.Furnace).size(), before,
		"a product the station cannot make is not added")
	if err != "":
		return err
	for recipe in recipes.get_recipes(Types.Item.Furnace):
		if recipe == null:
			return _T.assert_true(false, "a null recipe was appended")
	return ""


func test_loading_keeps_the_array_every_station_is_holding() -> String:
	# CraftingStation binds recipe_list = Recipes.get_recipes(type) by reference in
	# _ready. Reassigning the list on load left every station on the map pointing at
	# an orphaned array and blind to anything unlocked afterwards.
	var held = recipes.get_recipes(Types.Item.Sawmill)

	recipes.add_recipe(Types.Item.WoodWall, Types.Item.Sawmill)
	var saved: Dictionary = recipes.saveObject()
	# saveObject calls get_path(), which prints an error on this out-of-tree Recipes.
	# Asserting the payload first means an aborted save cannot reach the identity
	# check below and be mistaken for a pass (gather-1t9).
	var err: String = _T.assert_true(
		saved.has("sawmill_recipes") and not saved["sawmill_recipes"].is_empty(),
		"the save payload actually carries the unlocked sawmill recipes")
	if err != "":
		return err

	recipes.loadObject(saved)

	err = _T.assert_true(
		held == recipes.get_recipes(Types.Item.Sawmill),
		"the station's array is the same object after a load")
	if err != "":
		return err

	recipes.add_recipe(Types.Item.WoodDoor, Types.Item.Sawmill)
	for recipe in held:
		if recipe.product == Types.Item.WoodDoor:
			return ""
	return _T.assert_true(false, "a post-load unlock is invisible to the array stations hold")


func test_loading_tops_up_the_day_one_set() -> String:
	# A save written before a recipe joined the day-one set has no id for it, and
	# loadObject rebuilds the unlocked lists purely from those ids.
	var legacy := {
		"filepath": "/root/Recipes",
		"furnace_recipes": [],
		"sawmill_recipes": [JSON.stringify({"type": Types.Item.Chest})],
	}
	recipes.loadObject(legacy)
	return _T.assert_true(
		recipes.is_unlocked(Types.Item.Plank, Types.Item.Sawmill),
		"an old save still gets the plank")
