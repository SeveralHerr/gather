extends TextureRect
class_name SawmillUi

@export var sawmills= []
@export var selectedSawmill: Node
@export var itemManager: ItemManager
@export var items: Items
@export var inventoryManager: InventoryManager
var timer

# Called when the node enters the scene tree for the first time.
func _ready():
	$AddButton.connect("pressed", Callable(self, "_add"))
	$ExitButton.connect("pressed", Callable(self, "_close"))
	$ProducePlanksButton.connect("pressed", Callable(self, "_select_planks"))
	$ProduceWoodFloorButton.connect("pressed", Callable(self, "_select_floor"))

func _select_planks():
	var sawmill = GetCurrentSawmillData()
	sawmill.selectedProduction = GameItem.Type.Plank
	$ProducePlanksButton.modulate = Color(0, 0, 0, 200)
	$ProduceWoodFloorButton.modulate = Color(0, 0, 0, 0)
	pass
	
func _select_floor():
	var sawmill = GetCurrentSawmillData()
	sawmill.selectedProduction = GameItem.Type.WoodFloor
	$ProducePlanksButton.modulate = Color(0, 0, 0, 0)
	$ProduceWoodFloorButton.modulate = Color(0, 0, 0, 200)
	pass

# Called every frame. 'delta' is the elapsed time since the previous frame.
func _process(delta):
	pass

func test():
	print("test")
	
func AddInstance(data: SawmillData):
	var found = false
	for i in range(sawmills.size()):
		if sawmills[i].sawmill == data.sawmill:
			found = true
			
	if found == false:

		timer = Timer.new()
		timer.autostart = true
		add_child(timer)
		timer.connect("timeout", Callable(self, "_on_timeout"))
		data.timer = timer
		data.selectedProduction = GameItem.Type.Plank
		sawmills.append(data)


func _on_timeout():
	var sawmill = GetCurrentSawmillData()
	if sawmill.count > 0:
		itemManager.AddItemToWorld(sawmill.sawmill.position, items.Get(sawmill.selectedProduction))
		sawmill.count -= 1
		$QuantityLabel.text = "Qty " + str(sawmills[0].count)

func _add():
	var currentSawmill = GetCurrentSawmillData()
	#for item in range(inventoryManager.inventory.size()):
	if inventoryManager.HasItem(GameItem.Type.Wood):
		inventoryManager.RemoveItem(GameItem.Type.Wood)
		currentSawmill.count += 1
		$QuantityLabel.text = "Qty " + str(currentSawmill.count)
			
func GetCurrentSawmillData() -> SawmillData:
	for i in range(sawmills.size()):
		if sawmills[i].sawmill == selectedSawmill:
			return sawmills[i]
			
	return null

func _close():
	visible = false
