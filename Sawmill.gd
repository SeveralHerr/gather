extends Sprite2D
class_name Sawmill

signal sawmillClicked


# Called when the node enters the scene tree for the first time.
func _ready():
	add_to_group("Sawmills")
	$Button.connect("pressed", Callable(self, "_on_button_pressed"))

# Called every frame. 'delta' is the elapsed time since the previous frame.
func _process(delta):
	pass


func _on_button_pressed():
	var nodes = get_tree().get_nodes_in_group("UI")
	for node in nodes:
		if node is UI:

			node.test.visible = true
			
			if node.test is SawmillUi:
				node.test.AddInstance(SawmillData.new(self, 0))
				node.test.selectedSawmill = self
	#add_child(instance)
