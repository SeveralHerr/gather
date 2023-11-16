extends Resource
class_name CraftingRecipe

@export var product: Types.Item
@export var cost_list = {}

func _init(product: Types.Item, cost_list ):
	self.product = product
	self.cost_list = cost_list
