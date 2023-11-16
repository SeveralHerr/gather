extends AnimatedSprite2D

@onready var collider = $Area2D

# Called when the node enters the scene tree for the first time.
func _ready():
	collider.connect("body_entered", Callable(self, "_door_open"))
	collider.connect("body_exited", Callable(self, "_door_close"))
	pass # Replace with function body.


# Called every frame. 'delta' is the elapsed time since the previous frame.
func _process(delta):

	pass

func _door_open(body):
	if body is Player:
		play("Open")
	pass

func _door_close(body):
	if body is Player:
		play("Closed")
	pass
