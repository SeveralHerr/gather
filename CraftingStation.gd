extends Node2D
class_name CraftingStation

signal crafted_item(item: GameItem.Type, location: Vector2i)

@export var recipe_list = []
@export var selected_recipe: CraftingRecipe
@export var count: int
@export var type: GameItem.Type
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
	
	if type == GameItem.Type.Furnace:
		var iron_bar_costs = {}
		iron_bar_costs[GameItem.Type.CoalOre] = 1
		iron_bar_costs[GameItem.Type.IronOre] = 1
		recipe_list.append(CraftingRecipe.new(GameItem.Type.IronBar, iron_bar_costs))
		
		selected_recipe = recipe_list[0]
		
	if type == GameItem.Type.Sawmill:
		var plank_costs = {}
		plank_costs[GameItem.Type.Wood] = 1
		recipe_list.append(CraftingRecipe.new(GameItem.Type.Plank, plank_costs))
		
		var wood_floor_costs = {}
		wood_floor_costs[GameItem.Type.Wood] = 1
		recipe_list.append(CraftingRecipe.new(GameItem.Type.WoodFloor, wood_floor_costs))
		
		var wood_wall_costs = {}
		wood_wall_costs[GameItem.Type.Wood] = 1
		recipe_list.append(CraftingRecipe.new(GameItem.Type.WoodWall, wood_wall_costs))
		
		var wood_door_costs = {}
		wood_door_costs[GameItem.Type.Wood] = 1
		recipe_list.append(CraftingRecipe.new(GameItem.Type.WoodDoor, wood_door_costs))
				
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

	
	
	
	
