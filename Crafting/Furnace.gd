extends AnimatedSprite2D
class_name Furnace

signal furnanceClicked

var data: CraftingStationData


# Called when the node enters the scene tree for the first time.
func _ready():
	add_to_group("Sawmills")
	$Button.connect("pressed", Callable(self, "_on_button_pressed"))
	play("Off")

# Called every frame. 'delta' is the elapsed time since the previous frame.
func _process(delta):
	if data != null:
		if data.count > 0:
			play("On")
		elif data.count <= 0:
			play("Off")
	pass


func _on_button_pressed():
	var nodes = get_tree().get_nodes_in_group("UI")
	for node in nodes:
		if node is UI:

			node.furnaceUi.visible = true

			if node.furnaceUi is FurnaceUi:
				data = CraftingStationData.new(self, 0)
				node.furnaceUi.AddInstance(data)
				node.furnaceUi.selectedFurnace = self
	#add_child(instance)
