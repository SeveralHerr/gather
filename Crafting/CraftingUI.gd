extends ColorRect
class_name CraftingUi

@export var craftingStation: CraftingStation
@export var items: Items
@export var inventory_manager: InventoryManager
var amountToCraft = 0


var atlas_file = load("res://Resources/game_items_atlas.tres")
var costRow = preload("res://Crafting/CostRow.tscn")


# Called when the node enters the scene tree for the first time.
func _ready():
	add_to_group("CraftingUi")
	$AddButton.connect("pressed", Callable(self, "_add"))
	$ExitButton.connect("pressed", Callable(self, "_exit"))
	$CraftButton.connect("pressed", Callable(self, "_craft"))
	
	$Craftables.connect("item_selected",Callable( self, "_on_item_selected"))
	
	$QuantityLabel.text = "Qty. " + str(amountToCraft)
	pass # Replace with function body.


# Called every frame. 'delta' is the elapsed time since the previous frame.
func _process(delta):

	
	pass
	
func _on_item_selected(index):
	var selectedText = $Craftables.get_item_text(index)

	craftingStation.selected_recipe = _get_recipe_by_name(selectedText)
	var item = items.get_item(craftingStation.selected_recipe.product)			
	var atlas_texture = item.get_atlas()
	$SelectedCraftable.texture = atlas_texture
	
	for child in $CostList.get_children():
		child.queue_free()
			

	
	for costItemType in craftingStation.selected_recipe.cost_list.keys():
		var newCostRow = costRow.instantiate()
		$CostList.add_child(newCostRow)
		
		var citem = items.get_item(costItemType)				
		var catlas_texture = citem.get_atlas()
		newCostRow.texture = catlas_texture
		
		var text = citem.name + " "+ str(craftingStation.selected_recipe.cost_list[costItemType] * amountToCraft) + "/" + str(inventory_manager.get_quantity(costItemType))
		newCostRow.get_child(0).text = text
		
func _get_recipe_by_name(value):
	for recipe in craftingStation.recipe_list:
		var item = items.get_type(value)
		if item == recipe.product:
			return recipe

func load_crafting_station(craftingStation):
	visible = true
	self.craftingStation = craftingStation
	
	for child in $Craftables.get_children():
		child.queue_free()
		
	$Craftables.clear()
	print("Test")
	print(items.get_item(Types.Item.IronBar).name)
	for recipe in craftingStation.recipe_list:
		var item = items.get_item(recipe.product)		
		var atlas_texture = item.get_atlas()
		#add_child(instance)
		print(items.get_item(recipe.product).name)
		$Craftables.add_item( items.get_item(recipe.product).name, atlas_texture)
		
	var item = items.get_item(craftingStation.selected_recipe.product)			
	var atlas_texture = item.get_atlas()
	$SelectedCraftable.texture = atlas_texture
	
	for child in $CostList.get_children():
		child.queue_free()
			

	
	for costItemType in craftingStation.selected_recipe.cost_list.keys():
		var newCostRow = costRow.instantiate()
		$CostList.add_child(newCostRow)
		
		var citem = items.get_item(costItemType)				
		var catlas_texture = item.get_atlas()
		newCostRow.texture = catlas_texture
		
		
		var text = citem.name + " "+ str(craftingStation.selected_recipe.cost_list[costItemType] * amountToCraft) + "/" + str(inventory_manager.get_quantity(costItemType))
		newCostRow.get_child(0).text = text
	

	
func _add():
	var hasRequiredItems = []
	for item in craftingStation.selected_recipe.cost_list:
		hasRequiredItems.append(inventory_manager.HasItems(item, amountToCraft+1))

		
	for item in hasRequiredItems:
		if item == false:
			return
			
	
	var i = 0
	for costItemType in craftingStation.selected_recipe.cost_list.keys():	
		var item = items.get_item(costItemType)	
		var text = item.name + " "+ str(craftingStation.selected_recipe.cost_list[costItemType] * (amountToCraft+1)) + "/" + str(inventory_manager.get_quantity(costItemType))
		$CostList.get_child(i).get_child(0).text = text
		i += 1
			

	amountToCraft += 1
	$QuantityLabel.text = "Qty. " + str(amountToCraft)
	
func _craft():
	print("starting craft")
	for i in range(amountToCraft):			
		for item in craftingStation.selected_recipe.cost_list.keys():
			inventory_manager.RemoveItem(item)

	craftingStation.count = amountToCraft
	print("amount left", craftingStation.count)
	_exit()
	
func _exit():
	craftingStation = null
	amountToCraft = 0
	visible = false
