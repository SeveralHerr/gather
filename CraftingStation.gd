extends Node2D
class_name CraftingStation

signal crafted_item(item: GameItem.Type, location: Vector2i)

@export var recipe_list = []
@export var selected_recipe: CraftingRecipe
@export var count: int
@export var type: GameItem.Type
@export var timer: Timer

func _ready():
	add_to_group("CraftingStations")
	$Button.connect("pressed", Callable(self, "_on_button_open_crafting_station"))
	
	timer = Timer.new()
	timer.wait_time = 1
	add_child(timer)
	timer.connect("timeout", Callable(self, "_on_timeout"))
	
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
		
		selected_recipe = recipe_list[0]
	
func _process(delta):
	if count <= 0:
		timer.stop()
	elif count >0:
		timer.start()
		
func _on_timeout():
	count -= 1
	crafted_item.emit(selected_recipe.product, position)
	
func _on_button_open_crafting_station():
	var nodes = get_tree().get_nodes_in_group("CraftingUi")
	print("button")
	for node in nodes:
		if node is CraftingUi:
			print("loading")
			node.load_crafting_station(self)

	
	
	
	
