extends Node2D
class_name BoneTurret

var bullet = preload("res://Turrets/bullet.tscn")
var player: Player
var target: Node2D
@onready var sprite_2d = $LoadedSprite
@onready var shoot_timer = $ShootTimer
@onready var los: Area2D = $LineOfSight

var loaded: bool = false

# Called when the node enters the scene tree for the first time.
func _ready():
	los.connect("body_entered", Callable(self, "_on_body_entered"))
	los.connect("body_exited", Callable(self, "_on_body_exited"))

	shoot_timer.connect("timeout", Callable(self, "_on_timeout_shoot"))
	for node in get_tree().get_nodes_in_group("Player"):
		if node is Player:
			player = node
	pass # Replace with function body.

func _on_body_entered(body: Node2D):
	if target != null:
		return
		
	if loaded == false:
		return
		
	if body is Enemy:
		target = body

func _on_body_exited(body: Node2D):
	if body != target:
		return 		
	if loaded == false:
		return
		
	var nodes = los.get_overlapping_bodies()
	for node in nodes:
		if node is Enemy:
			target = node
			return 
	target = null
	
func set_loaded():
	loaded = true
	$LoadedSprite.visible = true
	$UnloadedSprite.visible = false

# Called every frame. 'delta' is the elapsed time since the previous frame.
func _process(delta):
	
	
	pass

func _on_timeout_shoot():
	if target == null:
		return
		
			
	if loaded == false:
		return
		
	var direction = (target.global_position - global_position).angle()
	var b = bullet.instantiate()
	b.start(Vector2.ZERO, direction)
	add_child(b)
