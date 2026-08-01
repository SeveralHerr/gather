extends Timer

## Drives continuous resource regrowth. There is no wave / phase concept: this
## fires forever, and ResourceManager2.add_random_resource() is what declines the
## spawn once the density-scaled cap is reached.

@export var tileMapHandler: TileMapHandler
@export var resourceManager: ResourceManager2


func _ready() -> void:
	# Belt and braces against the scene ever being saved with these flipped: a
	# one_shot or stopped timer means resources stop regrowing partway into a run,
	# which looks like a balance problem rather than a dead timer.
	one_shot = false
	if is_stopped():
		start()


func _on_timeout():
	if resourceManager == null:
		return
	resourceManager.add_random_resource()
