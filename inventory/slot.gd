extends PanelContainer
class_name NewSlot

signal slot_clicked(index: int, button: int)

@onready var texture_rect: TextureRect = $MarginContainer/TextureRect
@onready var quantity_label: Label = $QuantityLabel

func _ready():
	gui_input.connect(_on_gui_input)

			
func _on_gui_input(event: InputEvent) -> void:
	if event is InputEventMouseButton \
			and (event.button_index == MOUSE_BUTTON_LEFT \
			or event.button_index == MOUSE_BUTTON_RIGHT) \
			and event.is_pressed():
		slot_clicked.emit(get_index(), event.button_index)
	
func set_text(text):
	quantity_label.text = text

func set_slot_data(slot_data: SlotData) -> void:
	var item = slot_data.item
	if not item:
		return
	
	texture_rect.texture = item.get_atlas()
	tooltip_text = item.name
	
	if slot_data.count >= 1:
		quantity_label.text = "x%s" % slot_data.count
		quantity_label.show()
	else:
		quantity_label.hide()

