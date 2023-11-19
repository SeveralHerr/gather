extends Area2D

@export var target: Player = null

# Called when the node enters the scene tree for the first time.
func _ready():
	connect("body_entered", Callable(self, "_on_range"))
	connect("body_exited", Callable(self, "_on_range_exit"))
	pass # Replace with function body.

func _on_range(body: Node2D):
	if body is Player:
		target = body
	
func _on_range_exit(body: Node2D):
	target = null


func _on_body_entered(body):
	if body is Player:
		target = body


func _on_body_exited(body):
	target = null
