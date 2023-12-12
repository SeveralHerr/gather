extends Timer
@export var tileMapHandler: TileMapHandler
@export var resourceManager: ResourceManager2

func _on_timeout():
	resourceManager.add_random_resource()
