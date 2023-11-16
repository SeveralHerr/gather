extends Panel
class_name SlotButton

signal slot_clicked(inventory_slot_item: InventorySlot)

var inventory_slot_item: InventorySlot
@export var button: Button
@onready var ui = get_tree().get_nodes_in_group("UI")


# Called when the node enters the scene tree for the first time.
func _ready():
	add_to_group("Buttons")


func _on_button_pressed():
	print("click")
	slot_clicked.emit(inventory_slot_item)


