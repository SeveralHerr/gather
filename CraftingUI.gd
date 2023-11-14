extends ColorRect
class_name CraftingUi

@export var craftingStation: CraftingStation
@export var items: Items

var atlas_texture = AtlasTexture.new()
var costRow = preload("res://CostRow.tscn")


# Called when the node enters the scene tree for the first time.
func _ready():
	add_to_group("CraftingUi")
	$AddButton.connect("pressed", Callable(self, "_add"))
	$ExitButton.connect("pressed", Callable(self, "_exit"))
	
	atlas_texture.atlas = load("res://Resources/game_items_atlas.tres")
	
	
	pass # Replace with function body.


# Called every frame. 'delta' is the elapsed time since the previous frame.
func _process(delta):
	pass

func load_crafting_station(craftingStation):
	visible = true
	self.craftingStation = craftingStation
	
	for recipe in craftingStation.recipe_list:
		var instance = TextureRect.new()
		var item = items.Get(recipe.product)
		var location = Rect2(item.atlas_location.x*16, item.atlas_location.y*16, 16, 16)
		
		atlas_texture.region = location

		instance.texture = atlas_texture
		instance.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST 
		$Craftables.add_item(str(craftingStation.type), instance)
		
	var instance = TextureRect.new()
	var item = items.Get(craftingStation.selected_recipe.product)
	var location = Rect2(item.atlas_location.x*16, item.atlas_location.y*16, 16, 16)
	
	atlas_texture.region = location

	instance.texture = atlas_texture
	instance.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST 
	$SelectedCraftable.texture = instance
	
	for costItemType in craftingStation.selected_recipe.cost_list.keys():
		var newCostRow = costRow.instantiate()
		$CostList.add_child(newCostRow)
		
		var cinstance = TextureRect.new()
		var citem = items.Get(costItemType)
		var clocation = Rect2(item.atlas_location.x*16, item.atlas_location.y*16, 16, 16)
		
		atlas_texture.region = clocation

		cinstance.texture = atlas_texture
		cinstance.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST 
		newCostRow.texture = cinstance
		
		newCostRow.get_child(0).text = str(craftingStation.selected_recipe.cost_list[costItemType])
		
		
	
func _add():
	craftingStation.count += 1
	
func _exit():
	craftingStation = null
	visible = false
