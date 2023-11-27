extends Node2D
class_name CraftingStation

signal crafted_item(item: Types.Item, location: Vector2i)

@export var recipe_list = []
@export var selected_recipe: CraftingRecipe
@export var count: int
@export var type: Types.Item
@export var timer: Timer
@export var item_mamager: ItemManager

@onready var selected_item_manager: SelectedItemManager = $Node2D/Player/Camera2D/UI/SelectedItemManager


var starting_count: int = 0

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
	
	recipe_list = Recipes.get_recipes(type)
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
			
			var nodes2 = get_tree().get_nodes_in_group("SelectedItemManager")
			for node2 in nodes2:
				if node2 is SelectedItemManager:
					if node2.selected_inventory_slot_item == null:
						node.load_crafting_station(self)

	
	
	
	
