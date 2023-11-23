extends Node2D
class_name CraftingStation

signal crafted_item(item: Types.Item, location: Vector2i)

@export var recipe_list = []
@export var selected_recipe: CraftingRecipe
@export var count: int
@export var type: Types.Item
@export var timer: Timer
@export var item_mamager: ItemManager

func _ready():
	add_to_group("CraftingStations")
	$Button.connect("pressed", Callable(self, "_on_button_open_crafting_station"))
	
	timer = Timer.new()
	timer.wait_time = 1
	add_child(timer)
	timer.connect("timeout", Callable(self, "_on_timeout"))
	
	var nodes = get_tree().get_nodes_in_group("ItemManager")
	for node in nodes:
		if node is ItemManager:
			item_mamager = node
	
	if type == Types.Item.Furnace:
		var iron_bar_costs = {}
		iron_bar_costs[Types.Item.CoalOre] = 1
		iron_bar_costs[Types.Item.IronOre] = 1
		recipe_list.append(CraftingRecipe.new(Types.Item.IronBar, iron_bar_costs))
		
		selected_recipe = recipe_list[0]
		
	if type == Types.Item.Sawmill:
		var plank_costs = {}
		plank_costs[Types.Item.Wood] = 1
		recipe_list.append(CraftingRecipe.new(Types.Item.Plank, plank_costs))
		
		var wood_floor_costs = {}
		wood_floor_costs[Types.Item.Wood] = 1
		recipe_list.append(CraftingRecipe.new(Types.Item.WoodFloor, wood_floor_costs))
		
		var wood_wall_costs = {}
		wood_wall_costs[Types.Item.Wood] = 1
		recipe_list.append(CraftingRecipe.new(Types.Item.WoodWall, wood_wall_costs))
		
		var wood_door_costs = {}
		wood_door_costs[Types.Item.Wood] = 1
		recipe_list.append(CraftingRecipe.new(Types.Item.WoodDoor, wood_door_costs))
		
		var chest_costs = {}
		chest_costs[Types.Item.Wood] = 1
		recipe_list.append(CraftingRecipe.new(Types.Item.Chest, chest_costs))
		
		var bone_turret_costs = {}
		bone_turret_costs[Types.Item.Wood] = 1
		bone_turret_costs[Types.Item.IronBar] = 1
		bone_turret_costs[Types.Item.String] = 1
		recipe_list.append(CraftingRecipe.new(Types.Item.BoneTurret, bone_turret_costs))
		
		var net_costs = {}
		net_costs[Types.Item.Wood] = 5
		net_costs[Types.Item.String] = 5
		recipe_list.append(CraftingRecipe.new(Types.Item.Net, net_costs))
		
		var furnace_costs = {}
		furnace_costs[Types.Item.Stone] = 9
		recipe_list.append(CraftingRecipe.new(Types.Item.Furnace, furnace_costs))
				
		selected_recipe = recipe_list[0]
	
func _process(delta):
	if count <= 0:
		timer.stop()
	elif count >0:
		if timer.is_stopped():
			timer.start()
		
func _on_timeout():
	count -= 1
	item_mamager.AddItemToWorldByType(position, selected_recipe.product)
	
func _on_button_open_crafting_station():
	var nodes = get_tree().get_nodes_in_group("CraftingUi")
	for node in nodes:
		if node is CraftingUi:
			node.load_crafting_station(self)

	
	
	
	
