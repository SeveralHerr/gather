extends Node
class_name NewInventoryManager

const PICK_UP = preload("res://items/pick_up.tscn")

@onready var player: Player = $"../Node2D/Player"
@onready var inventory_interface = $"../UI2/InventoryInterface"
@onready var input_manager: InputManager = $"../InputManager"
@onready var hot_bar_inventory = $"../UI2/HotBarInventory"
@onready var crafting_ui: CraftingUi = $"../UI2/CraftingUI"

func _ready():
	add_to_group("InventoryManager")
	inventory_interface.drop_slot_data.connect(_on_drop_slot_data)
	input_manager.toggle_inventory.connect(_toggle_inventory)
	inventory_interface.set_player_inventory_data(player.inventory_data)
	inventory_interface.force_close.connect(_toggle_inventory)
	hot_bar_inventory.set_inventory_data(player.inventory_data)

	for node in get_tree().get_nodes_in_group("external_inventory"):
		if node is TestChest:
			node.toggle_inventory.connect(_toggle_inventory)

	# Stations are only ever instanced at runtime by the tilemap, long after this
	# runs, so they connect themselves in their own _ready. Nothing to sweep up here.


func _on_drop_slot_data(slot_data: SlotData):
	var pick_up = PICK_UP.instantiate()
	pick_up.slot_data = slot_data
	pick_up.position = player.position + Vector2(16,16)
	add_child(pick_up)
	pick_up.sprite_2d.texture = slot_data.item.get_atlas()
	
	
	
## The panel owns the whole open/close handshake now — cursor, disable_input and the
## hotbar — the way SkillTreeUi does. This is only the router from "the player pressed
## action on a station" to "show that station".
func _toggle_crafting_station(crafting_station = null) -> void:
	if crafting_station and not crafting_ui.is_open():
		crafting_ui.open_station(crafting_station)
	else:
		crafting_ui.set_open(false)


func _toggle_inventory(external_inventory_owner = null) -> void:
	inventory_interface.visible = not inventory_interface.visible
	# Assigned from the panel's own visibility, never toggled: a flip meant opening
	# this on top of another panel handed control back to the player mid-menu, and
	# closing it left input disabled for good.
	input_manager.disable_input = inventory_interface.visible

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
