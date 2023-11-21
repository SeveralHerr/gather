extends Node

var boneEnemy = preload("res://Enemies/BoneEnemy.tscn")
@onready var tilemap_handler: TileMapHandler = $"../.."

@onready var node_2d = $".."


@onready var timer: Timer = $Timer


# Called when the node enters the scene tree for the first time.
func _ready():
	timer.connect("timeout", Callable(self, "_timeout"))
	pass # Replace with function body.


# Called every frame. 'delta' is the elapsed time since the previous frame.
func _process(delta):
	pass

func _timeout():
	print("Bone Enemy")
	var pos = tilemap_handler.tileMap.map_to_local( tilemap_handler.get_random_tile())
	var instance = boneEnemy.instantiate()
	instance.position = pos
	node_2d.add_child(instance)
	pass
