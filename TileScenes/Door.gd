extends AnimatedSprite2D

@onready var collider = $Area2D
var sound_manager: SoundManager

# Called when the node enters the scene tree for the first time.
func _ready():
	collider.connect("body_entered", Callable(self, "_door_open"))
	collider.connect("body_exited", Callable(self, "_door_close"))
	
	var nodes = get_tree().get_nodes_in_group("SoundManager")
	for node in nodes:
		if node is SoundManager:
			sound_manager = node
	
	pass # Replace with function body.



func _door_open(body):
	if body is Player:
		play("Open")
		sound_manager.play_sound(sound_manager.SoundType.DOOR_ACTION)
	pass

func _door_close(body):
	if body is Player:
		play("Closed")
		sound_manager.play_sound(sound_manager.SoundType.DOOR_ACTION)
	pass
