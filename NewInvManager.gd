extends Node

const PICK_UP = preload("res://Items/PickUp.tscn")

@onready var player: Player = $"../Node2D/Player"
@onready var inventory_interface = $"../UI2/InventoryInterface"
@onready var input_manager: InputManager = $"../InputManager"
@onready var hot_bar_inventory = $"../UI2/HotBarInventory"
@onready var crafting_ui = $"../Node2D/Player/Camera2D/UI/CraftingUI"

func _ready():
	inventory_interface.drop_slot_data.connect(_on_drop_slot_data)
	input_manager.toggle_inventory.connect(_toggle_inventory)
	inventory_interface.set_player_inventory_data(player.inventory_data)
	inventory_interface.set_equip_inventory_data(player.equip_inventory_data)
	inventory_interface.set_equip_sword_inventory_data(player.equip_sword_inventory_data)
	inventory_interface.force_close.connect(_toggle_inventory)
	hot_bar_inventory.set_inventory_data(player.inventory_data)

	for node in get_tree().get_nodes_in_group("external_inventory"):
		if node is TestChest:
			node.toggle_inventory.connect(_toggle_inventory)

	for node in get_tree().get_nodes_in_group("CraftingStations"):
		if node is CraftingStation:
			node.toggle_crafting_station.connect(_toggle_crafting_station)
# Called every frame. 'delta' is the elapsed time since the previous frame.
func _process(delta):
	pass

	

func _on_drop_slot_data(slot_data: SlotData):
	var pick_up = PICK_UP.instantiate()
	pick_up.slot_data = slot_data
	pick_up.position = player.position + Vector2(16,16)
	add_child(pick_up)
	pick_up.sprite_2d.texture = slot_data.item.get_atlas()
	
	
	
func _toggle_crafting_station(crafting_station = null) -> void:
	crafting_ui.visible = not crafting_ui.visible
	
	if crafting_ui.visible:
		Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
		hot_bar_inventory.hide()
	else:
		Input.mouse_mode = Input.MOUSE_MODE_CAPTURED
		hot_bar_inventory.show()

	if crafting_station and crafting_ui.visible:
		crafting_ui.load_crafting_station(crafting_station)
	else:
		crafting_ui._exit()

	
func _toggle_inventory(external_inventory_owner = null) -> void:
	inventory_interface.visible = not inventory_interface.visible
	
	if inventory_interface.visible:
		Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
		hot_bar_inventory.hide()
	else:
		Input.mouse_mode = Input.MOUSE_MODE_CAPTURED
		hot_bar_inventory.show()

	if external_inventory_owner and inventory_interface.visible:
		inventory_interface.set_external_inventory(external_inventory_owner)
	else:
		inventory_interface.clear_external_inventory()
