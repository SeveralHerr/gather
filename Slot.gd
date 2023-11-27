extends Panel
class_name SlotButton

signal slot_clicked(inventory_slot_item: InventorySlot, instance: SlotButton)

var inventory_slot_item: InventorySlot
@onready var ui = get_tree().get_nodes_in_group("UI")

var normal_style: StyleBox
var highlighted_style: StyleBox

@onready var texture_rect = $MarginContainer/TextureRect
@onready var button = $MarginContainer/Button

# Called when the node enters the scene tree for the first time.
func _ready():
	add_to_group("Buttons")
	inventory_slot_item = InventorySlot.new(null, 0)
	#button.connect("")
	normal_style = button.get_theme_stylebox("normal")
	highlighted_style = StyleBoxFlat.new()
	highlighted_style.bg_color = Color(1, 1, 0) # Yellow color

func clear_slot():
	inventory_slot_item = null
	
func set_slot(inventory_slot: InventorySlot):
	inventory_slot_item = inventory_slot

func _on_button_pressed():
	if inventory_slot_item and inventory_slot_item.item == null:
		return
		
	#button.add_theme_stylebox_override("normal", highlighted_style)
	slot_clicked.emit(inventory_slot_item, self)


