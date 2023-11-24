extends Area2D
class_name FollowPlayer

var base_enemy: BaseEnemy
@onready var player: Player = get_tree().get_nodes_in_group("Player")[0]  


# Called when the node enters the scene tree for the first time.
func _ready():
	base_enemy = get_parent()
	
	connect("body_entered", Callable(self, "_on_body_entered"))
	connect("body_exited", Callable(self, "_on_body_exited"))
	pass # Replace with function body.
	
	
func _physics_process(delta):
	if base_enemy.target == null:
		return

	var distance = base_enemy.position.distance_to(player.position)
	if distance <= 10:
		base_enemy.speed = 0.01
	else:
		base_enemy.speed = 10


	var direction = to_local(navigation_agent_2d.get_next_path_position()).normalized()
	velocity = direction * speed + knockback
	
	move_and_slide()
	knockback = lerp(knockback, Vector2.ZERO, 0.1)
	
func create_path():
	if target == null:
		return
	navigation_agent_2d.target_position = target.global_position
	pass
	
	

func _on_timer_timeout():
	create_path()
	pass # Replace with function body.

func get_nearest_area2d(search_distance: int):
	var interactive_objects = los_area_2d.get_overlapping_areas()

	var minimum_distance = search_distance
	var nearest_object

	var current_position = global_position

	for object in interactive_objects:
		var distance = object.global_transform.origin.distance_squared_to(current_position)
		if distance < minimum_distance:
			minimum_distance = distance
			nearest_object = object


func _on_body_entered(body: Node2D):
	if body is Player:
		base_enemy.target = body

func _on_body_exited(body: Node2D):
	base_enemy.target = null
