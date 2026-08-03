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

	# Walks the master registry rather than two named lists, so a station added later is
	# held to this rule the moment its first recipe is registered — nobody has to remember
	# to come back and add a third loop here (gather-uaq).
	for station in recipes.master:
		for recipe in recipes.master[station]:
			if not reachable.has("%d@%d" % [recipe.product, station]):
				return _T.assert_true(false,
					"%s recipe '%s' is unlocked by nothing"
						% [items.get_item(station).name, items.get_item(recipe.product).name])
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
	# Station-keyed since gather-uaq: one "stations" object rather than a key per station,
	# so a third station persists with no format change. JSON object keys are strings, hence
	# the str() on the enum.
	var sawmill_key := str(Types.Item.Sawmill)
	var err: String = _T.assert_true(
		saved.has("stations") and saved["stations"].has(sawmill_key)
			and not saved["stations"][sawmill_key].is_empty(),
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


func test_a_pre_station_keyed_save_still_restores_both_stations() -> String:
	# The gather-uaq migration, and the only thing standing between the format change and
	# every existing save losing its unlock list. A v3 payload names its two stations
	# ("furnace_recipes" / "sawmill_recipes"); a v4 one carries a single station-keyed
	# "stations" object. Both must read, and not because loadObject consults a version
	# number — a v3 file migrated verbatim into a slot is still v3 on disk while this build
	# writes v4, so the shape is what has to be recognised (same reasoning as decode_entries).
	#
	# Products chosen because neither is in DAY_ONE_RECIPES: a recipe the seed would have
	# granted anyway proves nothing about whether the payload was read.
	var legacy := {
		"filepath": "/root/Recipes",
		"furnace_recipes": [{"type": Types.Item.IronBar}],
		"sawmill_recipes": [{"type": Types.Item.BoneTurret}],
	}
	recipes.loadObject(legacy)

	var err: String = _T.assert_true(
		recipes.is_unlocked(Types.Item.IronBar, Types.Item.Furnace),
		"the old payload's furnace recipe came back")
	if err != "":
		return err
	return _T.assert_true(
		recipes.is_unlocked(Types.Item.BoneTurret, Types.Item.Sawmill),
		"the old payload's sawmill recipe came back")


## The Recipes entry out of a committed save fixture, or {} if the file has none.
##
## Read from the real file rather than reconstructed, because the whole value of the
## fixtures is that nobody wrote them for this test — demo_homestead_save_v1 in particular
## predates the double-encoding removal and must never be regenerated (test/fixtures/README).
func _recipes_entry_from(path: String) -> Dictionary:
	var file := FileAccess.open(path, FileAccess.READ)
	if file == null:
		return {}
	while file.get_position() < file.get_length():
		var parsed: Variant = JSON.parse_string(file.get_line())
		if parsed is Dictionary and str(parsed.get("filepath", "")).ends_with("Recipes"):
			file.close()
			return parsed
	file.close()
	return {}


## Every product the payload claims is unlocked, whichever shape it is in, as "product@station".
func _claimed_unlocks(entry: Dictionary) -> Array:
	var claimed := []
	for legacy_key in recipes.LEGACY_SAVE_KEYS:
		for node in SaveLoad.decode_entries(entry.get(legacy_key, [])):
			if node.has("type"):
				claimed.append([int(node["type"]), recipes.LEGACY_SAVE_KEYS[legacy_key]])
	var stations: Variant = entry.get("stations", null)
	if stations is Dictionary:
		for station_key in stations:
			for node in SaveLoad.decode_entries(stations[station_key]):
				if node.has("type"):
					claimed.append([int(node["type"]), int(station_key)])
	return claimed


func test_the_committed_save_fixtures_still_restore_their_unlocks() -> String:
	# The gather-uaq format change against the two files that actually exist on disk, rather
	# than against a payload this test wrote for itself. saveFile is gitignored, so a broken
	# load is not something CI or a fresh clone would ever show — these fixtures are the only
	# standing check, and both predate the station-keyed payload.
	#
	# One file per shape the loader still has to read, which is the only reason there are
	# three: demo_homestead_save carries the current station-keyed payload,
	# demo_homestead_save_v3 the pre-gather-uaq per-station keys as nested dictionaries, and
	# demo_homestead_save_v1 the same keys double-encoded as JSON strings from before
	# gather-usv. The last two go through the legacy-key branch of loadObject, and v1 also
	# through decode_entries' String path.
	for path in [
		"res://test/fixtures/demo_homestead_save",
		"res://test/fixtures/demo_homestead_save_v3",
		"res://test/fixtures/demo_homestead_save_v1",
	]:
		var entry := _recipes_entry_from(path)
		var err: String = _T.assert_true(not entry.is_empty(), "%s has a Recipes entry" % path)
		if err != "":
			return err

		var claimed := _claimed_unlocks(entry)
		err = _T.assert_gt(claimed.size(), 0, "%s claims at least one unlocked recipe" % path)
		if err != "":
			return err

		recipes.loadObject(entry)

		for pair in claimed:
			if not recipes.is_unlocked(pair[0], pair[1]):
				return _T.assert_true(false,
					"%s: product %d at station %d was in the save and did not come back"
						% [path, pair[0], pair[1]])
	return ""


func test_a_station_id_that_came_through_json_finds_the_same_list() -> String:
	# Godot compares Dictionary keys by type as well as value, so 7.0 and 7 are two different
	# keys — and JSON has one number type, so every station id that has been through a save
	# file is a float. Unnormalised, get_recipes(7.0) does not merely miss: it CREATES a
	# second empty list beside the real one and returns that, so a station bound to it shows
	# nothing and never sees an unlock, silently.
	#
	# Found by asking the running game for get_recipes(7) over the devtools bus (which
	# marshals arguments as JSON) while the sawmill on screen was holding three recipes; the
	# call came back []. Nothing in the suite could see it, because the game itself only ever
	# passes Types.Item ints.
	var by_int: Array = recipes.get_recipes(Types.Item.Sawmill)
	var by_float: Array = recipes.get_recipes(float(Types.Item.Sawmill))

	var err: String = _T.assert_true(by_int == by_float, "a float station id finds the same array")
	if err != "":
		return err
	# And the array is the real one, not a fresh empty fork that happens to compare equal
	# when both are empty.
	return _T.assert_gt(by_float.size(), 0, "the array found by float id is the populated one")


func test_a_station_with_nothing_unlocked_hands_out_a_usable_array() -> String:
	# CraftingStation._ready does `recipe_list = Recipes.get_recipes(type)` and then
	# `recipe_list[0] if not recipe_list.is_empty()`. The old accessor returned null for any
	# station its if/elif did not name, so a station registered in items.gd but missing here
	# crashed on placement — on .is_empty() of a Nil — rather than simply having nothing to
	# make yet (gather-uaq).
	#
	# Chest is not a station at all, which is the point: this is the shape of the question a
	# station type nobody has written recipes for yet will ask.
	var held: Array = recipes.get_recipes(Types.Item.Chest)

	var err: String = _T.assert_true(held.is_empty(), "an unknown station starts empty")
	if err != "":
		return err
	# The same array, not a fresh empty one each call — a station placed before its first
	# unlock has to be holding the object that unlock will later append to.
	return _T.assert_true(
		held == recipes.get_recipes(Types.Item.Chest),
		"the array is stable across calls, so a station can bind to it")
