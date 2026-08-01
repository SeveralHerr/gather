extends Node

var furnace_recipe_list = []
var sawmill_recipe_list = []
var current_furnace_recipe_list = []
var current_sawmill_recipe_list = []
# Called when the node enters the scene tree for the first time.
func _ready():
	add_to_group("SaveLoad")
	furnace_recipes()
	sawmill_recipes()
	
	current_sawmill_recipe_list.append(get_sawmill_recipe(Types.Item.Chest))
	
func get_recipes(type):
	if type == Types.Item.Sawmill:
		return current_sawmill_recipe_list
	if type == Types.Item.Furnace:
		return current_furnace_recipe_list
func get_sawmill_recipe(type):
	for recipe in sawmill_recipe_list:
		if recipe.product == type:
			return recipe
			
func get_furnace_recipe(type):
	for recipe in furnace_recipe_list:
		if recipe.product == type:
			return recipe

func furnace_recipes():
	# Copper is the first metal the furnace ever sees — it is unlocked by the same
	# skill that unlocks the furnace itself, so it has to be the cheapest bar in the
	# game: one ore, one coal, exactly like iron but from a commoner-to-reach node.
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

func sawmill_recipes():
	var plank_costs = {}
	plank_costs[Types.Item.Wood] = 1
	sawmill_recipe_list.append(CraftingRecipe.new(Types.Item.Plank, plank_costs))
	
	var wood_floor_costs = {}
	wood_floor_costs[Types.Item.Wood] = 1
	sawmill_recipe_list.append(CraftingRecipe.new(Types.Item.WoodFloor, wood_floor_costs))
	
	var wood_wall_costs = {}
	wood_wall_costs[Types.Item.Wood] = 1
	sawmill_recipe_list.append(CraftingRecipe.new(Types.Item.WoodWall, wood_wall_costs))
	
	var wood_door_costs = {}
	wood_door_costs[Types.Item.Wood] = 1
	sawmill_recipe_list.append(CraftingRecipe.new(Types.Item.WoodDoor, wood_door_costs))
	
	var chest_costs = {}
	chest_costs[Types.Item.Wood] = 1
	sawmill_recipe_list.append(CraftingRecipe.new(Types.Item.Chest, chest_costs))
	
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
	
	var net_costs = {}
	net_costs[Types.Item.Wood] = 5
	net_costs[Types.Item.String] = 5
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
			


func add_recipe(recipe: Types.Item, type ):
	if type == Types.Item.Furnace:
		current_furnace_recipe_list.append(get_furnace_recipe(recipe))
	elif type == Types.Item.Sawmill:
		current_sawmill_recipe_list.append(get_sawmill_recipe(recipe))

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
	current_furnace_recipe_list = []
	current_sawmill_recipe_list = []
	
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
