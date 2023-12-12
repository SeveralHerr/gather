extends Resource
class_name CraftingRecipe

@export var product: Types.Item
@export var cost_list = {}

func _init(_product: Types.Item, _cost_list ):
	self.product = _product
	self.cost_list = _cost_list
