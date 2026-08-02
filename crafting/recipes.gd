extends Node

var furnace_recipe_list = []
var sawmill_recipe_list = []
var current_furnace_recipe_list = []
var current_sawmill_recipe_list = []

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


func get_recipes(type):
	if type == Types.Item.Sawmill:
		return current_sawmill_recipe_list
	if type == Types.Item.Furnace:
		return current_furnace_recipe_list


## Every recipe the station can ever make, unlocked or not. The crafting panel shows
## locked recipes greyed out rather than hiding them — a recipe the player cannot see
## is a skill they have no reason to buy.
func all_recipes(type):
	if type == Types.Item.Sawmill:
		return sawmill_recipe_list
	if type == Types.Item.Furnace:
		return furnace_recipe_list
	return []


func is_unlocked(product: Types.Item, type) -> bool:
	for recipe in get_recipes(type):
		if recipe and recipe.product == product:
			return true
	return false


func get_sawmill_recipe(type):
	for recipe in sawmill_recipe_list:
		if recipe.product == type:
			return recipe
			
func get_furnace_recipe(type):
	for recipe in furnace_recipe_list:
		if recipe.product == type:
			return recipe

func furnace_recipes():
	# Copper is the first metal the furnace ever sees, and its veins spawn unlocked, so
	# the player reaches this recipe already holding the ore. It has to be the cheapest
	# bar in the game: one ore, one coal, exactly like iron but from a commoner node.
	var copper_bar_costs = {}
	copper_bar_costs[Types.Item.CoalOre] = 1
	copper_bar_costs[Types.Item.CopperOre] = 1
	furnace_recipe_list.append(CraftingRecipe.new(Types.Item.CopperBar, copper_bar_costs))

	var iron_bar_costs = {}
	iron_bar_costs[Types.Item.CoalOre] = 1
	iron_bar_costs[Types.Item.IronOre] = 1
	furnace_recipe_list.append(CraftingRecipe.new(Types.Item.IronBar, iron_bar_costs))

	# Gold is alloyed, not smelted straight. The copper bar in here is deliberate: it
	# is what stops copper becoming a dead tier the moment iron is unlocked, and it
	# makes the gold bar cost two ore types plus double fuel without needing a new
	# item to carry the difference.
	var gold_bar_costs = {}
	gold_bar_costs[Types.Item.CoalOre] = 2
	gold_bar_costs[Types.Item.GoldOre] = 1
	gold_bar_costs[Types.Item.CopperBar] = 1
	furnace_recipe_list.append(CraftingRecipe.new(Types.Item.GoldBar, gold_bar_costs))

	# Charcoal. Coal is the only ore with a single consumer and it is also the input
	# every furnace recipe needs, so a run that rolls badly on coal veins stalls the
	# entire Industry branch. Six wood is deliberately worse than finding a vein — this
	# is the floor that stops a stall, not a replacement for mining.
	var charcoal_costs = {}
	charcoal_costs[Types.Item.Wood] = 6
	furnace_recipe_list.append(CraftingRecipe.new(Types.Item.CoalOre, charcoal_costs))

	# Minting. Gold veins pay a coin only half the time and coins are the only thing
	# land can be bought with, so map expansion is otherwise pure luck on the rarest
	# node in the game. Struck from ore rather than from a bar on purpose: it competes
	# with the gold bar for the same input instead of sitting downstream of it, so the
	# ore goes on the map or on the pickaxe, not both.
	var coin_costs = {}
	coin_costs[Types.Item.GoldOre] = 1
	coin_costs[Types.Item.CoalOre] = 1
	furnace_recipe_list.append(CraftingRecipe.new(Types.Item.Coin, coin_costs))

func sawmill_recipes():
	var plank_costs = {}
	plank_costs[Types.Item.Wood] = 1
	sawmill_recipe_list.append(CraftingRecipe.new(Types.Item.Plank, plank_costs))
	
	# The building set is priced in planks rather than raw wood. Until the crafting
	# panel started charging the quantities it displayed, every one of these was "1
	# wood" and the plank was a step you could skip entirely; costing them in the
	# sawmill's own output is what gives the first recipe in the list a reason to exist.
	var wood_floor_costs = {}
	wood_floor_costs[Types.Item.Plank] = 1
	sawmill_recipe_list.append(CraftingRecipe.new(Types.Item.WoodFloor, wood_floor_costs))

	var wood_wall_costs = {}
	wood_wall_costs[Types.Item.Plank] = 2
	sawmill_recipe_list.append(CraftingRecipe.new(Types.Item.WoodWall, wood_wall_costs))

	var wood_door_costs = {}
	wood_door_costs[Types.Item.Plank] = 3
	sawmill_recipe_list.append(CraftingRecipe.new(Types.Item.WoodDoor, wood_door_costs))

	var chest_costs = {}
	chest_costs[Types.Item.Plank] = 4
	sawmill_recipe_list.append(CraftingRecipe.new(Types.Item.Chest, chest_costs))

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
	sawmill_recipe_list.append(CraftingRecipe.new(Types.Item.StoneFloor, stone_floor_costs))

	var stone_wall_costs = {}
	stone_wall_costs[Types.Item.Stone] = 3
	sawmill_recipe_list.append(CraftingRecipe.new(Types.Item.StoneWall, stone_wall_costs))

	# The first tool the player can build, and the first thing stone is for. Stone and
	# scene-stone together are roughly half of everything that spawns (spawn_weight
	# 4.0 + 4.0 out of 16.7 in Resources.TUNING), and before this its only sink in the
	# whole game was the one furnace you ever need. Eight is about four nodes' worth:
	# affordable inside the opening minutes, which is exactly when the surplus appears.
	var stone_pickaxe_costs = {}
	stone_pickaxe_costs[Types.Item.Stone] = 8
	stone_pickaxe_costs[Types.Item.Wood] = 2
	sawmill_recipe_list.append(CraftingRecipe.new(Types.Item.StonePickaxe, stone_pickaxe_costs))

	# A second sawmill. A station makes one item per second, so another one is parallel
	# throughput rather than a convenience — and the player has been handed exactly one
	# since player.gd:66 with no way to ever build another. Priced in planks so it
	# cannot be the first thing built with the wood off three trees.
	var sawmill_costs = {}
	sawmill_costs[Types.Item.Wood] = 10
	sawmill_costs[Types.Item.Plank] = 4
	sawmill_recipe_list.append(CraftingRecipe.new(Types.Item.Sawmill, sawmill_costs))

	# Twine. String had no craftable source of any kind — it dropped from spiders and
	# nowhere else, which left the Net and the Bone Turret (a whole Combat tier) hostage
	# to which enemy the spawner happened to roll. Wood is the one thing always in
	# surplus, so this is a guaranteed floor under the spider drop, not a replacement
	# for it.
	var string_costs = {}
	string_costs[Types.Item.Wood] = 3
	sawmill_recipe_list.append(CraftingRecipe.new(Types.Item.String, string_costs))

	# Copper rather than iron on purpose. The turret is a Combat-branch unlock, and
	# pricing it in iron bars made it secretly depend on Industry tier 2; copper bars
	# come with the furnace at Industry tier 1, so a Combat player can now actually
	# reach the thing their own branch just gave them. It also gives copper a sink
	# that exists before gold does.
	var bone_turret_costs = {}
	bone_turret_costs[Types.Item.Wood] = 1
	bone_turret_costs[Types.Item.CopperBar] = 2
	bone_turret_costs[Types.Item.String] = 1
	sawmill_recipe_list.append(CraftingRecipe.new(Types.Item.BoneTurret, bone_turret_costs))
	
	# Was 5 wood + 5 string, i.e. five spider kills for one single-use item. With twine
	# craftable the number can come down, and the wood half moves to planks so the
	# sawmill's own output has somewhere to go.
	var net_costs = {}
	net_costs[Types.Item.Plank] = 2
	net_costs[Types.Item.String] = 3
	sawmill_recipe_list.append(CraftingRecipe.new(Types.Item.Net, net_costs))
	
	var furnace_costs = {}
	furnace_costs[Types.Item.Stone] = 9
	sawmill_recipe_list.append(CraftingRecipe.new(Types.Item.Furnace, furnace_costs))
	
	var bone_pickaxe_costs = {}
	bone_pickaxe_costs[Types.Item.Bone] = 9
	sawmill_recipe_list.append(CraftingRecipe.new(Types.Item.BonePickaxe, bone_pickaxe_costs))
	
	# Gated behind the furnace: iron bars are the whole point of unlocking iron, so the
	# top-tier pickaxe should cost them rather than repeating the bone pickaxe's price.
	var iron_pickaxe_costs = {}
	iron_pickaxe_costs[Types.Item.IronBar] = 5
	iron_pickaxe_costs[Types.Item.Plank] = 2
	sawmill_recipe_list.append(CraftingRecipe.new(Types.Item.IronPickaxe, iron_pickaxe_costs))

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
	sawmill_recipe_list.append(CraftingRecipe.new(Types.Item.CopperPickaxe, copper_pickaxe_costs))

	var gold_pickaxe_costs = {}
	gold_pickaxe_costs[Types.Item.GoldBar] = 5
	gold_pickaxe_costs[Types.Item.Plank] = 4
	sawmill_recipe_list.append(CraftingRecipe.new(Types.Item.GoldPickaxe, gold_pickaxe_costs))
			


## Unlocks `recipe` at `type`. Guards against both duplicates and misses: the day-one
## seed now runs on load as well as at boot, and a product that no longer exists in
## the master list would otherwise append a null that every consumer dereferences.
func add_recipe(recipe: Types.Item, type ):
	if is_unlocked(recipe, type):
		return

	var found = null
	if type == Types.Item.Furnace:
		found = get_furnace_recipe(recipe)
	elif type == Types.Item.Sawmill:
		found = get_sawmill_recipe(recipe)

	if found == null:
		push_warning("Recipes: no recipe for product %s at station %s" % [recipe, type])
		return

	get_recipes(type).append(found)

func saveObject() -> Dictionary:
	var current_furnace_recipe_list_json = []
	var current_sawmill_recipe_list_json = []

	for i in current_furnace_recipe_list.size():
		var json := {
			"type": current_furnace_recipe_list[i].product
		}
	
		current_furnace_recipe_list_json.append(JSON.stringify(json))
		
	for i in current_sawmill_recipe_list.size():
		var json := {
			"type": current_sawmill_recipe_list[i].product
		}
	
		current_sawmill_recipe_list_json.append(JSON.stringify(json))	
	
		
	var dict := {
		"filepath": get_path(),
		"furnace_recipes": current_furnace_recipe_list_json,
		"sawmill_recipes": current_sawmill_recipe_list_json
	}
	return dict
	
func loadObject(loadedDict: Dictionary) -> void:
	# Cleared in place, never reassigned. Every live CraftingStation captured this
	# exact array by reference in its _ready (recipe_list = Recipes.get_recipes(type)),
	# so handing out a fresh [] leaves every station on the map bound to an orphan and
	# blind to anything unlocked afterwards.
	current_furnace_recipe_list.clear()
	current_sawmill_recipe_list.clear()

	_seed_day_one()

	for i in loadedDict.furnace_recipes.size():
		var saved_info = loadedDict.furnace_recipes[i]
		var json = JSON.new()
		json.parse(saved_info)
		var node = json.get_data()
		
		add_recipe(node["type"], Types.Item.Furnace)
		
	for i in loadedDict.sawmill_recipes.size():
		var saved_info = loadedDict.sawmill_recipes[i]
		var json = JSON.new()
		json.parse(saved_info)
		var node = json.get_data()
		
		add_recipe(node["type"], Types.Item.Sawmill)
