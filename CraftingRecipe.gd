extends Resource
class_name CraftingRecipe

@export var product: GameItem.Type
@export var cost_list = {}

func _init(product: GameItem.Type, cost_list ):
	self.product = product
	self.cost_list = cost_list
