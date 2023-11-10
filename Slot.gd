extends Panel
class_name SlotButton

@export var item: Item
@onready var ui = get_tree().get_nodes_in_group("UI")


# Called when the node enters the scene tree for the first time.
func _ready():
	pass # Replace with function body.


# Called every frame. 'delta' is the elapsed time since the previous frame.
func _process(delta):
	pass


func _on_button_pressed():
	for i in ui: 
		if i is UI:
			i.selectedItem = item
			i.SelectItem()
