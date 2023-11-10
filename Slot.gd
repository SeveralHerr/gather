extends Panel
class_name SlotButton

signal slot_clicked(item: Item)

@export var item: Item
@export var button: Button
@onready var ui = get_tree().get_nodes_in_group("UI")


# Called when the node enters the scene tree for the first time.
func _ready():
	add_to_group("Buttons")


func _on_button_pressed():
	slot_clicked.emit(item)
func test():
	print(get_index())
	print("index")
	for i in ui: 
		if i is UI:
			print("fdsa")
			i.selectedItem = item
			i.SelectItem()


func _on_gui_input(event: InputEvent):
	print("T")
	if event is InputEventMouseButton and (event.button_index == MOUSE_BUTTON_LEFT):
		print("test")
