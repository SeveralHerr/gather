extends CharacterBody2D
class_name BaseEnemy

@onready var line_of_sight = $LineOfSight
@onready var attack_range = $AttackRange

var target: Node2D

var health_manager: HealthManager = HealthManager.new(10)
var damage = 3
var speed = 10

# Called when the node enters the scene tree for the first time.
func _ready():
	health_manager.new(10)
	
	line_of_sight.connect("body_entered", Callable(self, "_on_body_entered"))
	line_of_sight.connect("body_exited", Callable(self, "_on_body_exited"))
	pass # Replace with function body.


# Called every frame. 'delta' is the elapsed time since the previous frame.
func _process(delta):
	pass
