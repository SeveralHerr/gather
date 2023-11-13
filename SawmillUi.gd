extends TextureRect
class_name SawmillUi

@export var sawmills: Array[SawmillData] = []
@export var itemManager: ItemManager
@export var items: Items
@export var inventoryManager: InventoryManager

# Called when the node enters the scene tree for the first time.
func _ready():
	$AddButton.connect("pressed", Callable(self, "_add"))
	$ExitButton.connect("pressed", Callable(self, "_close"))

# Called every frame. 'delta' is the elapsed time since the previous frame.
func _process(delta):
	pass

func test():
	print("test")


func _on_resource_timer_timeout():
	for sawmill in sawmills: 
		if sawmill.count > 0:
			itemManager.AddItemToWorld(sawmill.sawmill.position, items.Get(GameItem.Type.Plank))
			sawmill.count -= 1
			$QuantityLabel.text = "Qty " + str(sawmills[0].count)

func _add():
	for item in range(inventoryManager.inventory.size()):
		if inventoryManager.HasItem(GameItem.Type.Wood):
			inventoryManager.RemoveItem(GameItem.Type.Wood)
			sawmills[0].count += 1
			$QuantityLabel.text = "Qty " + str(sawmills[0].count)

func _close():
	visible = false
