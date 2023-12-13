extends Sprite2D

var target: Node2D
var is_grounded = false

# Called when the node enters the scene tree for the first time.
func _ready():
	pass # Replace with function body.


# Called every frame. 'delta' is the elapsed time since the previous frame.
func _process(_delta):
	position.x = target.position.x
	
	if is_grounded:
		position.y= target.position.y
	pass
