extends Control

signal drop_slot_data(slot_data: SlotData)
signal force_close

var grabbed_slot_data: SlotData
var external_inventory_owner

@onready var player_inventory: NewInventory = $PlayerInventory
@onready var grabbed_slot: NewSlot  = $GrabbedSlot
@onready var external_inventory: NewInventory = $ExternalInventory
@onready var equip_inventory = $EquipInventory
@onready var equip_sword_inventory = $EquipSwordInventory
@onready var input_manager: InputManager = $"../../InputManager"


func _ready():
	gui_input.connect(_on_gui_input)
	visibility_changed.connect(_on_visibility_changed)

func _physics_process(delta):
	if grabbed_slot.visible:
		grabbed_slot.global_position = get_global_mouse_position() + Vector2(5,5)

	if external_inventory_owner \
			and external_inventory_owner.global_position.distance_to(PlayerManager.get_global_position()) > 15:
		force_close.emit()

func _on_visibility_changed():
	if not visible and grabbed_slot_data:
		drop_slot_data.emit(grabbed_slot_data)
		grabbed_slot_data = null
		update_grabbed_slot()

func _on_gui_input(event: InputEvent):
	if event is InputEventMouseButton	\
			and event.is_pressed() \
			and grabbed_slot_data:
				
		match event.button_index:
			MOUSE_BUTTON_LEFT:
				drop_slot_data.emit(grabbed_slot_data)
				grabbed_slot_data = null
			MOUSE_BUTTON_RIGHT:
				drop_slot_data.emit(grabbed_slot_data.create_single_slot_data())
				if grabbed_slot_data.count < 1:
					grabbed_slot_data = null
				
		update_grabbed_slot()

func set_player_inventory_data(inventory_data: InventoryData) -> void:
	inventory_data.inventory_interact.connect(on_inventory_interact)
	player_inventory.set_inventory_data(inventory_data)
	
func on_inventory_interact(inventory_data: InventoryData, index: int, button: int ):
	print("%s %s %s" % [inventory_data, index, button])
	
	match [grabbed_slot_data, button]:
		[null, MOUSE_BUTTON_LEFT]:
			grabbed_slot_data = inventory_data.grab_slot_data(index)
		# Something is in the slot data
		[_, MOUSE_BUTTON_LEFT]:
			grabbed_slot_data = inventory_data.drop_slot_data(grabbed_slot_data, index)

		[null, MOUSE_BUTTON_RIGHT]:
			inventory_data.use_slot_data(index)
		# Something is in the slot data
		[_, MOUSE_BUTTON_RIGHT]:
			grabbed_slot_data = inventory_data.drop_single_slot_data(grabbed_slot_data, index)
			
	update_grabbed_slot()

func update_grabbed_slot() -> void:
	if grabbed_slot_data:
		grabbed_slot.show()
		grabbed_slot.set_slot_data(grabbed_slot_data)
	else: 
		grabbed_slot.hide()
		
func set_external_inventory(_external_inventory_owner):
	external_inventory_owner = _external_inventory_owner
	var inventory_data = external_inventory_owner.inventory_data
	
	inventory_data.inventory_interact.connect(on_inventory_interact)
	external_inventory.set_inventory_data(inventory_data)
	
	external_inventory.show()
	input_manager.disable_input = true
	
func clear_external_inventory():
	if not external_inventory_owner:
		return 
		
	var inventory_data = external_inventory_owner.inventory_data
	
	inventory_data.inventory_interact.disconnect(on_inventory_interact)
	external_inventory.clear_inventory_data(inventory_data)
	
	external_inventory.hide()
	external_inventory_owner = null
	input_manager.disable_input = false
