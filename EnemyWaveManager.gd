extends Node

var boneEnemy = preload("res://Enemies/BoneEnemy.tscn")
var spiderEnemy = preload("res://Enemies/SpiderEnemy.tscn")
@onready var tilemap_handler: TileMapHandler = $"../.."

@onready var node_2d = $".."


@onready var timer: Timer = $Timer

var enemies = [boneEnemy, spiderEnemy]

# Called when the node enters the scene tree for the first time.
func _ready():
	randomize()
	timer.connect("timeout", Callable(self, "_timeout"))
	pass # Replace with function body.


# Called every frame. 'delta' is the elapsed time since the previous frame.
func _process(delta):
	pass

func _timeout():
	var random_index = randi() % enemies.size()	
	var enemy_to_spawn = enemies[random_index]
	var pos = tilemap_handler.tileMap.map_to_local( tilemap_handler.get_random_tile())
	var instance = enemy_to_spawn.instantiate()
	instance.position = pos
	node_2d.add_child(instance)
	pass
