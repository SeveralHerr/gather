extends Node

@onready var player: Player = $"../Node2D/Player"
@onready var inventory_interface = $"../UI2/InventoryInterface"
@onready var input_manager: InputManager = $"../InputManager"

func _ready():
	input_manager.toggle_inventory.connect(_toggle_inventory)
	inventory_interface.set_player_inventory_data(player.inventory_data)

	for node in get_tree().get_nodes_in_group("external_inventory"):
		node.toggle_inventory.connect(_toggle_inventory)
# Called every frame. 'delta' is the elapsed time since the previous frame.
func _process(delta):
	pass

func _toggle_inventory(external_inventory_owner = null) -> void:
	inventory_interface.visible = not inventory_interface.visible
	
	if inventory_interface.visible:
		Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
	else:
		Input.mouse_mode = Input.MOUSE_MODE_CAPTURED

	if external_inventory_owner and inventory_interface.visible:
		inventory_interface.set_external_inventory(external_inventory_owner)
	else:
		inventory_interface.clear_external_inventory()
