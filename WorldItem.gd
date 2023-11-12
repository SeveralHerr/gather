extends Resource
class_name WorldItem

@export var item: Item

@export var instance: TextureRect


func _init(item: Item, position: Vector2i):
	self.item = item
	self.instance = TextureRect.new()
	self.instance.texture_filter = CanvasItem.TEXTURE_FILTER_MAX
	self.instance.position = position
