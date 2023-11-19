extends TextureRect
class_name FurnaceUi

@export var furnaces: Array[CraftingStationData]= []
@export var selectedFurnace: Node
@export var itemManager: ItemManager
@export var items: Items
@export var inventoryManager: InventoryManager
var timer

# Called when the node enters the scene tree for the first time.
func _ready():
	$AddButton.connect("pressed", Callable(self, "_add"))
	$ExitButton.connect("pressed", Callable(self, "_close"))

# Called every frame. 'delta' is the elapsed time since the previous frame.
func _process(delta):
	pass

func test():
	print("test")
	
func AddInstance(data: CraftingStationData):
	var found = false
	for i in range(furnaces.size()):
		if furnaces[i].craftingStation == data.craftingStation:
			found = true
			
	if found == false:

		timer = Timer.new()
		timer.autostart = true
		add_child(timer)
		timer.connect("timeout", Callable(self, "_on_timeout"))
		data.timer = timer
		data.selectedProduction = GameItem.Type.IronBar
		furnaces.append(data)


func _on_timeout():
	var currentFurnace = GetCurrentSawmillData()
	if currentFurnace.count > 0:
		itemManager.AddItemToWorld(currentFurnace.craftingStation.position, items.Get(currentFurnace.selectedProduction))
		currentFurnace.count -= 1
		$QuantityLabel.text = "Qty " + str(furnaces[0].count)

func _add():
	var currentFurnace = GetCurrentSawmillData()
	#for item in range(inventoryManager.inventory.size()):
	if inventoryManager.HasItem(GameItem.Type.IronOre) and inventoryManager.HasItem(GameItem.Type.CoalOre):
		inventoryManager.RemoveItem(GameItem.Type.IronOre)
		inventoryManager.RemoveItem(GameItem.Type.CoalOre)
		currentFurnace.count += 1
		$QuantityLabel.text = "Qty " + str(currentFurnace.count)
			
func GetCurrentSawmillData() -> CraftingStationData:
	for i in range(furnaces.size()):
		if furnaces[i].craftingStation == selectedFurnace:
			return furnaces[i]
			
	return null

func _close():
	visible = false
