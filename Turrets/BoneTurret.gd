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
	add_to_group("SaveChunks")
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


func _on_timeout_shoot():
	if target == null:
		return
		
			
	if loaded == false:
		return
		
	var direction = (target.global_position - global_position).angle()
	var b = bullet.instantiate()
	b.start(Vector2.ZERO, direction)
	add_child(b)

func save():
	var bullet_data = {}
	var bullets = get_children()
	for i in bullets.size():
		if bullets[i] is Bullet:
			var json = {
				"x": bullets[i].position.x,
				"y": bullets[i].position.y,
				"rotation": bullets[i].rotation,
				"velocityx": bullets[i].velocity.x,
				"velocityy": bullets[i].velocity.y,
				"loaded": loaded
			}
			bullet_data[i] = JSON.stringify(json)
	
	var dict = {
		"x": position.x,
		"y": position.y,
		"data": bullet_data,
		"filepath": "343"
	}

	return dict
	
func load(dict):
	for child in get_children(): 
		if child is Bullet:
			child.queue_free()
	
	for item in dict.data.keys():
		var x = dict.data[item]
		var json = JSON.new()
		json.parse(x)
		var node = json.get_data()
		
		if  node["loaded"] == true:
			set_loaded()
		var b = bullet.instantiate()
		add_child(b)
		b.velocity = Vector2( node["velocityx"],node["velocityy"])

		var nodes = los.get_overlapping_bodies()
		for e in nodes:
			if e is Enemy:
				target = e
				return 
