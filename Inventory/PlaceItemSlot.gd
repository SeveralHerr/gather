extends PanelContainer
class_name PlaceItemSlot

signal slot_use(index: int, button: int)

@onready var texture_rect: TextureRect = $TextureRect

func _ready():
	gui_input.connect(_on_gui_input)

			
func _on_gui_input(event: InputEvent) -> void:
	if Input.is_action_just_pressed("gather"):
		slot_use.emit(get_index(), event.button_index)
	

func set_slot_data(slot_data: SlotData) -> void:
	var item = slot_data.item
	if not item:
		return
	
	texture_rect.texture = item.get_atlas()

