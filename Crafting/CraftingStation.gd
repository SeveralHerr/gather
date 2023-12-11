extends Node2D
class_name CraftingStation

signal crafted_item(item: Types.Item, location: Vector2i)
signal toggle_crafting_station(crafting_station)

@export var recipe_list = []
@export var selected_recipe: CraftingRecipe
@export var count: int
@export var type: Types.Item
@export var timer: Timer
@onready var new_inv_manager = get_tree().get_nodes_in_group("InventoryManager")[1]  
@onready var selected_item_manager: SelectedItemManager = $Node2D/Player/Camera2D/UI/SelectedItemManager


var starting_count: int = 0

@export var inventory_data: InventoryData

func player_interact() -> void:
	toggle_crafting_station.emit(self)
	#toggle_inventory.emit(self)

func _ready():
	add_to_group("external_inventory")
	add_to_group("CraftingStations")
	$Button.connect("pressed", Callable(self, "_on_button_open_crafting_station"))
	
	timer = Timer.new()
	timer.wait_time = 1
	add_child(timer)
	timer.connect("timeout", Callable(self, "_on_timeout"))
	
	recipe_list = Recipes.get_recipes(type)
	selected_recipe = recipe_list[0]
	toggle_crafting_station.connect(new_inv_manager._toggle_crafting_station)
	
	
func _process(delta):
	if count <= 0:
		timer.stop()
	elif count >0:
		if timer.is_stopped():
			timer.start()
		
func _on_timeout():
	count -= 1
	PickUpManager.create_pickup(GameItems.get_item( selected_recipe.product), position + Vector2(0, 6))
	
func _on_button_open_crafting_station():
	var nodes = get_tree().get_nodes_in_group("CraftingUi")
	for node in nodes:
		if node is CraftingUi:
			
			var nodes2 = get_tree().get_nodes_in_group("SelectedItemManager")
			for node2 in nodes2:
				if node2 is SelectedItemManager:
					if node2.selected_inventory_slot_item == null:
						node.load_crafting_station(self)

func set_crafting_station(crafting_station):
	pass
func clear_crafting_station():
	pass
	
	
	
