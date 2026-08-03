extends Node

## Every recipe in the game, keyed by the station that makes it.
##
## Both dictionaries are Types.Item (the station) -> Array[CraftingRecipe]. They used to be
## four hand-named arrays with an if/elif chain per accessor, which meant a third station was
## a seven-place edit — two vars, get_recipes, all_recipes, get_*_recipe, saveObject and
## loadObject — plus the if/elif in crafting_station.gd. It is now one _register() call per
## recipe and nothing else (gather-uaq).
##
## The arrays in `unlocked` are handed out by reference and mutated in place, never
## reassigned. Every live CraftingStation captures its own in _ready (recipe_list =
## Recipes.get_recipes(type)), so replacing one leaves that station bound to an orphan and
## blind to everything unlocked afterwards.

## Everything the station can ever make, unlocked or not.
var master: Dictionary = {}

## What the player has actually unlocked, in unlock order.
var unlocked: Dictionary = {}

## What every save starts with, and what every save is topped up to on load. The
## plank belongs here rather than on a skill: three of the four pickaxes cost planks,
## and for a long time nothing unlocked the recipe at all — it sat in the master list
## while no skill and no seed ever moved it across, which quietly made the copper,
## iron and gold pickaxes uncraftable on a clean save.
const DAY_ONE_RECIPES := [
	{"product": Types.Item.Plank, "station": Types.Item.Sawmill},
	{"product": Types.Item.StonePickaxe, "station": Types.Item.Sawmill},
	{"product": Types.Item.Chest, "station": Types.Item.Sawmill},
]

## The save keys the two original stations were written under, before the payload became
## station-keyed. Read on load and never written again; see loadObject.
const LEGACY_SAVE_KEYS := {
	"furnace_recipes": Types.Item.Furnace,
	"sawmill_recipes": Types.Item.Sawmill,
}


# Called when the node enters the scene tree for the first time.
func _ready():
	add_to_group("SaveLoad")
	furnace_recipes()
	sawmill_recipes()

	_seed_day_one()


## Re-applied after every load, not just at boot. loadObject rebuilds the unlocked
## lists purely from the ids in the save file, so without this a recipe added to the
## day-one set would never reach a character that already exists.
func _seed_day_one() -> void:
	for entry in DAY_ONE_RECIPES:
		add_recipe(entry["product"], entry["station"])


## Normalises a station id to the int both dictionaries are keyed by.
##
## Godot compares Dictionary keys by type as well as value, so `7.0` and `7` are two
## different keys. JSON has one number type, so every station id that has been through a save
## file arrives as a float — and an unnormalised lookup does not merely miss, it silently
## creates a SECOND empty list beside the real one and hands that out. A station bound to
## that fork would show no recipes and never see an unlock, with nothing logged anywhere.
##
## Found by asking the running game for `get_recipes(7)` over the devtools bus, which
## marshals its arguments as JSON: the station on screen was holding three recipes and the
## call came back `[]`.
static func _key(station) -> int:
	return int(station)


## Adds `recipe` to what `station` can ever make. The one call a new recipe needs.
func _register(station: Types.Item, recipe: CraftingRecipe) -> void:
	var key := _key(station)
	if not master.has(key):
		master[key] = []
	master[key].append(recipe)


## What the player can currently make at `station`.
##
## Creates the array on first ask rather than returning a shared empty one, because callers
## hold on to it: a furnace placed before anything is unlocked at it must bind to the same
## array that a later skill purchase appends to. Returning null here — which is what the old
## if/elif did for any station it did not name — meant a station type registered in items.gd
## but missing from this file crashed on placement, on `.is_empty()` of a Nil.
func get_recipes(station) -> Array:
	var key := _key(station)
	if not unlocked.has(key):
		unlocked[key] = []
	return unlocked[key]


## Every recipe the station can ever make, unlocked or not. The crafting panel shows
## locked recipes greyed out rather than hiding them — a recipe the player cannot see
## is a skill they have no reason to buy.
func all_recipes(station) -> Array:
	return master.get(_key(station), [])


func is_unlocked(product: Types.Item, station) -> bool:
	for recipe in get_recipes(station):
		if recipe and recipe.product == product:
			return true
	return false


## The master-list recipe making `product` at `station`, or null.
func get_recipe(station, product) -> CraftingRecipe:
	for recipe in all_recipes(station):
		if recipe.product == product:
			return recipe
	return null


## Kept because tests and crafting_station.gd's loader name them. Thin wrappers now — the
## station is an argument, not a function name.
func get_sawmill_recipe(product) -> CraftingRecipe:
	return get_recipe(Types.Item.Sawmill, product)


func get_furnace_recipe(product) -> CraftingRecipe:
	return get_recipe(Types.Item.Furnace, product)


func furnace_recipes():
	# Copper is the first metal the furnace ever sees, and its veins spawn unlocked, so
	# the player reaches this recipe already holding the ore. It has to be the cheapest
	# bar in the game: one ore, one coal, exactly like iron but from a commoner node.
	var copper_bar_costs = {}
	copper_bar_costs[Types.Item.CoalOre] = 1
	copper_bar_costs[Types.Item.CopperOre] = 1
	_register(Types.Item.Furnace, CraftingRecipe.new(Types.Item.CopperBar, copper_bar_costs))

	var iron_bar_costs = {}
	iron_bar_costs[Types.Item.CoalOre] = 1
	iron_bar_costs[Types.Item.IronOre] = 1
	_register(Types.Item.Furnace, CraftingRecipe.new(Types.Item.IronBar, iron_bar_costs))

	# Gold is alloyed, not smelted straight. The copper bar in here is deliberate: it
	# is what stops copper becoming a dead tier the moment iron is unlocked, and it
	# makes the gold bar cost two ore types plus double fuel without needing a new
	# item to carry the difference.
	var gold_bar_costs = {}
	gold_bar_costs[Types.Item.CoalOre] = 2
	gold_bar_costs[Types.Item.GoldOre] = 1
	gold_bar_costs[Types.Item.CopperBar] = 1
	_register(Types.Item.Furnace, CraftingRecipe.new(Types.Item.GoldBar, gold_bar_costs))

	# Charcoal. Coal is the only ore with a single consumer and it is also the input
	# every furnace recipe needs, so a run that rolls badly on coal veins stalls the
	# entire Industry branch. Six wood is deliberately worse than finding a vein — this
	# is the floor that stops a stall, not a replacement for mining.
	var charcoal_costs = {}
	charcoal_costs[Types.Item.Wood] = 6
	_register(Types.Item.Furnace, CraftingRecipe.new(Types.Item.CoalOre, charcoal_costs))

	# Minting. Gold veins pay a coin only half the time and coins are the only thing
	# land can be bought with, so map expansion is otherwise pure luck on the rarest
	# node in the game. Struck from ore rather than from a bar on purpose: it competes
	# with the gold bar for the same input instead of sitting downstream of it, so the
	# ore goes on the map or on the pickaxe, not both.
	var coin_costs = {}
	coin_costs[Types.Item.GoldOre] = 1
	coin_costs[Types.Item.CoalOre] = 1
	_register(Types.Item.Furnace, CraftingRecipe.new(Types.Item.Coin, coin_costs))

	# --- Furnace additions (gather-cte).
	#
	# Cooking. Food drops from trees at a 0.2 chance and heals 4; two of them plus fuel heal
	# 10, so the furnace is what turns a forager's incidental drops into real sustain. It is
	# also the first furnace recipe whose inputs are not ore, which is the point — the machine
	# should be worth walking to for something other than metal.
	var cooked_food_costs = {}
	cooked_food_costs[Types.Item.Food] = 2
	cooked_food_costs[Types.Item.CoalOre] = 1
	_register(Types.Item.Furnace, CraftingRecipe.new(Types.Item.CookedFood, cooked_food_costs))

	# Firing brick. Stone is the resource the player trips over most (spawn_weight 4.0 + 4.0
	# of 16.7 in Resources.TUNING) and its only sinks are the furnace itself, one wall and one
	# floor. This gives the surplus somewhere to go and coal a consumer that is not a bar.
	var stone_brick_costs = {}
	stone_brick_costs[Types.Item.Stone] = 4
	stone_brick_costs[Types.Item.CoalOre] = 1
	_register(Types.Item.Furnace, CraftingRecipe.new(Types.Item.StoneBrick, stone_brick_costs))

func sawmill_recipes():
	var plank_costs = {}
	plank_costs[Types.Item.Wood] = 1
	_register(Types.Item.Sawmill, CraftingRecipe.new(Types.Item.Plank, plank_costs))

	# The building set is priced in planks rather than raw wood. Until the crafting
	# panel started charging the quantities it displayed, every one of these was "1
	# wood" and the plank was a step you could skip entirely; costing them in the
	# sawmill's own output is what gives the first recipe in the list a reason to exist.
	var wood_floor_costs = {}
	wood_floor_costs[Types.Item.Plank] = 1
	_register(Types.Item.Sawmill, CraftingRecipe.new(Types.Item.WoodFloor, wood_floor_costs))

	var wood_wall_costs = {}
	wood_wall_costs[Types.Item.Plank] = 2
	_register(Types.Item.Sawmill, CraftingRecipe.new(Types.Item.WoodWall, wood_wall_costs))

	var wood_door_costs = {}
	wood_door_costs[Types.Item.Plank] = 3
	_register(Types.Item.Sawmill, CraftingRecipe.new(Types.Item.WoodDoor, wood_door_costs))

	var chest_costs = {}
	chest_costs[Types.Item.Plank] = 4
	_register(Types.Item.Sawmill, CraftingRecipe.new(Types.Item.Chest, chest_costs))

	# The stone building set. Priced in raw stone rather than in a worked intermediate
	# because stone has no sawmill step of its own - the plank is what makes the wood
	# set cost two gathers, and here the second gather is simply more stone. Both sit
	# a little above their wood twin (3 vs 2 planks for the wall, 2 vs 1 for the floor)
	# so the tier reads as the sturdier, more expensive option rather than a reskin,
	# but stone outspawns trees by a wide margin in Resources.TUNING, so in practice
	# this is the cheaper wall to actually build - which is the point of putting it
	# one tier up the Building branch rather than gating it behind the furnace.
	var stone_floor_costs = {}
	stone_floor_costs[Types.Item.Stone] = 2
	_register(Types.Item.Sawmill, CraftingRecipe.new(Types.Item.StoneFloor, stone_floor_costs))

	var stone_wall_costs = {}
	stone_wall_costs[Types.Item.Stone] = 3
	_register(Types.Item.Sawmill, CraftingRecipe.new(Types.Item.StoneWall, stone_wall_costs))

	# The first tool the player can build, and the first thing stone is for. Stone and
	# scene-stone together are roughly half of everything that spawns (spawn_weight
	# 4.0 + 4.0 out of 16.7 in Resources.TUNING), and before this its only sink in the
	# whole game was the one furnace you ever need. Eight is about four nodes' worth:
	# affordable inside the opening minutes, which is exactly when the surplus appears.
	var stone_pickaxe_costs = {}
	stone_pickaxe_costs[Types.Item.Stone] = 8
	stone_pickaxe_costs[Types.Item.Wood] = 2
	_register(Types.Item.Sawmill, CraftingRecipe.new(Types.Item.StonePickaxe, stone_pickaxe_costs))

	# A second sawmill. A station makes one item per second, so another one is parallel
	# throughput rather than a convenience — and the player has been handed exactly one
	# since player.gd:66 with no way to ever build another. Priced in planks so it
	# cannot be the first thing built with the wood off three trees.
	var sawmill_costs = {}
	sawmill_costs[Types.Item.Wood] = 10
	sawmill_costs[Types.Item.Plank] = 4
	_register(Types.Item.Sawmill, CraftingRecipe.new(Types.Item.Sawmill, sawmill_costs))

	# Twine. String had no craftable source of any kind — it dropped from spiders and
	# nowhere else, which left the Net and the Bone Turret (a whole Combat tier) hostage
	# to which enemy the spawner happened to roll. Wood is the one thing always in
	# surplus, so this is a guaranteed floor under the spider drop, not a replacement
	# for it.
	var string_costs = {}
	string_costs[Types.Item.Wood] = 3
	_register(Types.Item.Sawmill, CraftingRecipe.new(Types.Item.String, string_costs))

	# Copper rather than iron on purpose. The turret is a Combat-branch unlock, and
	# pricing it in iron bars made it secretly depend on Industry tier 2; copper bars
	# come with the furnace at Industry tier 1, so a Combat player can now actually
	# reach the thing their own branch just gave them. It also gives copper a sink
	# that exists before gold does.
	var bone_turret_costs = {}
	bone_turret_costs[Types.Item.Wood] = 1
	bone_turret_costs[Types.Item.CopperBar] = 2
	bone_turret_costs[Types.Item.String] = 1
	_register(Types.Item.Sawmill, CraftingRecipe.new(Types.Item.BoneTurret, bone_turret_costs))

	# Was 5 wood + 5 string, i.e. five spider kills for one single-use item. With twine
	# craftable the number can come down, and the wood half moves to planks so the
	# sawmill's own output has somewhere to go.
	var net_costs = {}
	net_costs[Types.Item.Plank] = 2
	net_costs[Types.Item.String] = 3
	_register(Types.Item.Sawmill, CraftingRecipe.new(Types.Item.Net, net_costs))

	# The one thing on the list that removes the player from a loop rather than
	# speeding it up, so it is priced as a middle-of-the-run project, not a purchase.
	# Bone is the load-bearing number: the skull that assembles this comes off a bone
	# enemy, so the frame costs the same fight that fills it, and until now bone had
	# exactly one sink in the whole game (the pickaxe, at 9) the way stone had only the
	# furnace. Six leaves the pickaxe the larger single ask. The iron bars are what stop
	# a second worker being an afterthought - three bars is three ore plus three coal
	# against the iron pickaxe's five and five, so the tier's headline tool still wins
	# a straight comparison - and the planks make the thing that farms wood cost wood.
	# The real price is higher than the list: a worker is dead weight without a Net
	# (Combat tier 2) and a skull captured with it.
	var bone_worker_costs = {}
	bone_worker_costs[Types.Item.Bone] = 6
	bone_worker_costs[Types.Item.IronBar] = 3
	bone_worker_costs[Types.Item.Plank] = 4
	_register(Types.Item.Sawmill, CraftingRecipe.new(Types.Item.BoneWorker, bone_worker_costs))

	# The grey sibling, priced level with the blue one and deliberately not cheaper: it
	# automates the OTHER day-one resource, and a player who has one wants the pair. Stone
	# replaces the planks because that is what it goes on to farm, and the bone and iron are
	# untouched - the frame and the skull cost the same whatever the machine ends up mining.
	var stone_worker_costs = {}
	stone_worker_costs[Types.Item.Bone] = 6
	stone_worker_costs[Types.Item.IronBar] = 3
	stone_worker_costs[Types.Item.Stone] = 8
	_register(Types.Item.Sawmill, CraftingRecipe.new(Types.Item.StoneWorker, stone_worker_costs))

	var furnace_costs = {}
	furnace_costs[Types.Item.Stone] = 9
	_register(Types.Item.Sawmill, CraftingRecipe.new(Types.Item.Furnace, furnace_costs))

	var bone_pickaxe_costs = {}
	bone_pickaxe_costs[Types.Item.Bone] = 9
	_register(Types.Item.Sawmill, CraftingRecipe.new(Types.Item.BonePickaxe, bone_pickaxe_costs))

	# Gated behind the furnace: iron bars are the whole point of unlocking iron, so the
	# top-tier pickaxe should cost them rather than repeating the bone pickaxe's price.
	var iron_pickaxe_costs = {}
	iron_pickaxe_costs[Types.Item.IronBar] = 5
	iron_pickaxe_costs[Types.Item.Plank] = 2
	_register(Types.Item.Sawmill, CraftingRecipe.new(Types.Item.IronPickaxe, iron_pickaxe_costs))

	# The top of the ladder, and it should read as an undertaking rather than one more
	# rung. Same shape as the iron pickaxe (bars + planks) so the comparison is
	# obvious, but every gold bar underneath it already cost a gold ore, a copper bar
	# and two coal - so this is really 5 gold ore + 5 copper ore + 15 coal + 4 wood,
	# out of the rarest node on the island.
	# The tool copper exists for. Cheap on purpose — it arrives with the furnace, well
	# before bone becomes affordable, so it is the bridge out of the wooden pickaxe
	# rather than a competitor to the tiers above it.
	var copper_pickaxe_costs = {}
	copper_pickaxe_costs[Types.Item.CopperBar] = 3
	copper_pickaxe_costs[Types.Item.Plank] = 1
	_register(Types.Item.Sawmill, CraftingRecipe.new(Types.Item.CopperPickaxe, copper_pickaxe_costs))

	var gold_pickaxe_costs = {}
	gold_pickaxe_costs[Types.Item.GoldBar] = 5
	gold_pickaxe_costs[Types.Item.Plank] = 4
	_register(Types.Item.Sawmill, CraftingRecipe.new(Types.Item.GoldPickaxe, gold_pickaxe_costs))

	# --- The sword ladder (gather-cte). Combat had no craftable of its own: every one of its
	# skills was a stat bump or a turret, so a player pushing that branch crafted nothing at
	# their own stations. Each tier hangs off a skill the player already had a reason to buy,
	# so none of them needs a new node — the tree is capped at 16 by the XP budget a single
	# run can produce (test_skill_tree.test_the_whole_tree_is_reachable_in_one_run).
	#
	# Priced deliberately BELOW the pickaxe of the same tier: the pickaxe is the tool that
	# compounds (it makes everything else faster), so it should stay the bigger ask. Bone at 6
	# against the bone pickaxe's 9; iron at 4 bars against the iron pickaxe's 5; gold at 4
	# against 5.
	var bone_sword_costs = {}
	bone_sword_costs[Types.Item.Bone] = 6
	bone_sword_costs[Types.Item.Plank] = 2
	_register(Types.Item.Sawmill, CraftingRecipe.new(Types.Item.BoneSword, bone_sword_costs))

	var iron_sword_costs = {}
	iron_sword_costs[Types.Item.IronBar] = 4
	iron_sword_costs[Types.Item.Plank] = 2
	_register(Types.Item.Sawmill, CraftingRecipe.new(Types.Item.IronSword, iron_sword_costs))

	var gold_sword_costs = {}
	gold_sword_costs[Types.Item.GoldBar] = 4
	gold_sword_costs[Types.Item.Plank] = 3
	_register(Types.Item.Sawmill, CraftingRecipe.new(Types.Item.GoldSword, gold_sword_costs))

	# The Combat branch's sustain, and the second thing string is for. Costing it in string
	# rather than in food is what makes it Combat's own: spiders drop string, so the branch
	# that fights is the branch that heals.
	var bandage_costs = {}
	bandage_costs[Types.Item.String] = 2
	bandage_costs[Types.Item.Food] = 1
	_register(Types.Item.Sawmill, CraftingRecipe.new(Types.Item.Bandage, bandage_costs))



## Unlocks `recipe` at `station`. Guards against both duplicates and misses: the day-one
## seed now runs on load as well as at boot, and a product that no longer exists in
## the master list would otherwise append a null that every consumer dereferences.
func add_recipe(recipe: Types.Item, station):
	if is_unlocked(recipe, station):
		return

	var found := get_recipe(station, recipe)
	if found == null:
		push_warning("Recipes: no recipe for product %s at station %s" % [recipe, station])
		return

	get_recipes(station).append(found)


func saveObject() -> Dictionary:
	# Station-keyed, so a new station persists with no change here. JSON object keys are
	# always strings, so the station id is written as one and parsed back with int() below —
	# the same round trip every other enum in the save format makes.
	var stations := {}
	for station in unlocked:
		var products := []
		for recipe in unlocked[station]:
			products.append({"type": recipe.product})
		stations[str(station)] = products

	return {
		"filepath": get_path(),
		"stations": stations,
	}


func loadObject(loadedDict: Dictionary) -> void:
	# Cleared in place, never reassigned. Every live CraftingStation captured its own array
	# by reference in its _ready (recipe_list = Recipes.get_recipes(type)), so handing out a
	# fresh [] leaves every station on the map bound to an orphan and blind to anything
	# unlocked afterwards.
	for station in unlocked:
		unlocked[station].clear()

	_seed_day_one()

	# Structural, not version-branched: a save written before the payload became
	# station-keyed has no "stations" key and two named ones instead, and both shapes have to
	# be readable at once because a v3 file migrated verbatim into a slot is still v3 on disk
	# while this build writes v4. Same reasoning as decode_entries (gather-usv).
	var stations: Variant = loadedDict.get("stations", null)
	if stations is Dictionary:
		for station_key in stations:
			_load_station(int(station_key), stations[station_key])
		return

	for legacy_key in LEGACY_SAVE_KEYS:
		_load_station(LEGACY_SAVE_KEYS[legacy_key], loadedDict.get(legacy_key, []))


## Replays one station's unlocked list. decode_entries reads both the pre-gather-usv JSON
## strings and the nested dictionaries written now, and .get keeps a payload with no such key
## from raising (gather-xc0).
func _load_station(station: int, raw: Variant) -> void:
	for node in SaveLoad.decode_entries(raw):
		if node.has("type"):
			add_recipe(int(node["type"]), station)
