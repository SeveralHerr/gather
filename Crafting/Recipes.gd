extends Node

var furnace_recipe_list = []
var sawmill_recipe_list = []
var current_furnace_recipe_list = []
var current_sawmill_recipe_list = []
# Called when the node enters the scene tree for the first time.
func _ready():
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
	var iron_bar_costs = {}
	iron_bar_costs[Types.Item.CoalOre] = 1
	iron_bar_costs[Types.Item.IronOre] = 1
	furnace_recipe_list.append(CraftingRecipe.new(Types.Item.IronBar, iron_bar_costs))
	
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
	
	var bone_turret_costs = {}
	bone_turret_costs[Types.Item.Wood] = 1
	bone_turret_costs[Types.Item.IronBar] = 1
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
			


func add_recipe(recipe: Types.Item, type ):
	if type == Types.Item.Furnace:
		current_furnace_recipe_list.append(get_furnace_recipe(recipe))
	elif type == Types.Item.Sawmill:
		current_sawmill_recipe_list.append(get_sawmill_recipe(recipe))

# Called every frame. 'delta' is the elapsed time since the previous frame.
func _process(delta):
	pass
