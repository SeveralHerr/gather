extends Control
class_name UI
var inventory
@export var inventoryManager: InventoryManager
@export var Slot = preload("res://Slot.tscn")
@export var item_grid: GridContainer
@export var tileMapHandler: TileMapHandler
var selectedItem
var selectedTexture = TextureRect.new()

	

func _ready():
	add_to_group("UI")
	for child in item_grid.get_children():
		child.queue_free()
		
	for item in range(8):
		var slot = Slot.instantiate()
		item_grid.add_child(slot)
		
func _physics_process(delta):
	if selectedTexture != null:
		var mouse_pos = get_global_mouse_position()
		var tile_pos = tileMapHandler.tileMap.local_to_map(mouse_pos)
		var clamped_world_pos = tileMapHandler.tileMap.map_to_local(tile_pos)
		clamped_world_pos -= Vector2(16, 16) / 2

		# Set the object's position to the clamped position
		selectedTexture.position = clamped_world_pos

func add_item():
	update_ui()

func remove_item(item):
	update_ui()

func update_ui():
	for i in inventoryManager.inventory.size():
		var button = item_grid.get_child(i).get_child(0).get_child(1)
		#button.connect("pressed", Callable(self, "_on_Button_pressed"))

		item_grid.get_child(i).get_child(0).get_child(0).texture = inventoryManager.inventory[i].item.icon
		item_grid.get_child(i).get_child(1).text = str(inventoryManager.inventory[i].count)
		
		var slotButton = item_grid.get_child(i)
		if slotButton is SlotButton:
			slotButton.item = inventoryManager.inventory[i].item

func SelectItem():
	if selectedItem == null:
		return

	selectedTexture.texture = selectedItem.icon
	tileMapHandler.add_child(selectedTexture)

func fupdate_ui():
	# Clear the existing UI
	for child in $Panel/GridContainer.get_children():
		child.queue_free()
	
	print(inventoryManager.inventory)
	for item in inventoryManager.inventory.keys():
		var button = Button.new()
		$Panel/GridContainer.add_child(button)
				
		var item_icon = TextureRect.new()
		item_icon.texture = item.icon # Assuming each item has an 'icon' property
		$Panel/GridContainer.get_child(0).add_child(item_icon)
		




		button.connect("pressed", Callable(self, "_on_Button_pressed"))
		
		var label = Label.new()
		label.text = str(inventoryManager.inventory[item])
		label.scale *= 0.3
		$Panel/GridContainer.add_child(label)
		
