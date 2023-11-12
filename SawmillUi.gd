extends TextureRect
class_name SawmillUi

@export var sawmills: Array[SawmillData] = []
@export var itemManager: ItemManager
@export var items: Items

# Called when the node enters the scene tree for the first time.
func _ready():
	pass

# Called every frame. 'delta' is the elapsed time since the previous frame.
func _process(delta):
	pass

func test():
	print("test")


func _on_resource_timer_timeout():
	print("print")
	for sawmill in sawmills: 
		itemManager.AddItemToWorld(sawmill.sawmill.position, items.GetItemByName("Plank"))
