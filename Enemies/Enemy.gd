extends CharacterBody2D
class_name Enemy

const SPEED = 300.0
const JUMP_VELOCITY = -400.0

var target: Player
@export var attack_target: Player

@export var health_manager: HealthManager
@export var damage = 3
var camera: Camera

@export var items: Items
var gravity = ProjectSettings.get_setting("physics/2d/default_gravity")
@onready var navigation_agent_2d = $NavigationAgent2D
@onready var los_area_2d = $LineOfSight
@onready var player = $"../Player"

@onready var player_area_2d = $"../Player/Area2D"
@onready var attack_range = $AttackRange
@onready var sprite_2d = $Sprite2D

var item_manager: ItemManager

var detection_range = 100
var speed = 10
var knockback = Vector2.ZERO

var raycast: RayCast2D

func _ready():
	los_area_2d.connect("body_entered", Callable(self, "_on_body_entered"))
	los_area_2d.connect("body_exited", Callable(self, "_on_body_exited"))
	
	health_manager = HealthManager.new(10)
	health_manager.connect("died", Callable(self, "_on_died"))
	
	for node in get_tree().get_nodes_in_group("ItemManager"):
		if node is ItemManager:
			item_manager = node

	for node in get_tree().get_nodes_in_group("Items"):
		if node is Items:
			items = node
			
	for node in get_tree().get_nodes_in_group("Camera"):
		if node is Camera:
			camera = node

	attack_range.connect("body_entered", Callable(self, "_on_body_attack_entered"))
	attack_range.connect("body_exited", Callable(self, "_on_body_attack_exited"))
	# Initialize the raycast
	raycast = RayCast2D.new()
	raycast.enabled = true
	raycast.target_position = Vector2(100, 0)  # Adjust this to your desired range
	add_child(raycast)
	
	
func _on_died():
	$HitParticles.emitting = true
	await get_tree().create_timer(0.1).timeout
	$HitParticles.emitting = false
	await get_tree().create_timer(0.1).timeout
	item_manager.AddItemToWorld(position, items.get_item(Types.Item.Bone))
	queue_free()

func _process(delta):
	pass
func _on_body_entered(body: Node2D):
	if body is Player:
		target = body

func _on_player_detected():
	print("Player detected!")

func _on_body_exited(body: Node2D):
	target = null
	
func _on_body_attack_entered(body: Node2D):
	if body is Player:
		attack_target = body


func _on_body_attack_exited(body: Node2D):
	attack_target = null

func has_lost_line_of_sight() -> bool:

	var space_state = get_world_2d().get_direct_space_state()

	var params = PhysicsRayQueryParameters3D.new()

	params.from = Vector3(global_transform.origin.x, global_transform.origin.y, 0) + Vector3.UP

	params.to =Vector3(player.global_transform.origin.x, player.global_transform.origin.y, 0)

	params.exclude = []

	params.collision_mask = 1

	var result = space_state.intersect_ray(params)

	if result:

		return false

	return true


func d_process(delta):
	target = get_nearest_area2d(1000)

func _physics_process(delta):
	if target == null:
		return

	var distance = position.distance_to(player.position)
	if distance <= 10:
		speed = 0.01
	else:
		speed = 10


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

		return object
		
func receive_hit(force: Vector2, damage: int):
	add_central_force(force)
	health_manager.take_damage(damage)
	camera.apply_shake(1)
	$HitParticles.emitting = true
	await get_tree().create_timer(0.1).timeout
	$HitParticles.emitting = false
func add_central_force(force: Vector2):
	knockback = force

	sprite_2d.material = sprite_2d.material.duplicate()
	sprite_2d.material.set_shader_parameter("flash_intensity", 4)
	await get_tree().create_timer(0.1).timeout
	sprite_2d.material.set_shader_parameter("flash_intensity", 0)


func _on_attack_timer_timeout():
	if attack_target == null:
		return
		
	var direction = (attack_target.global_position - global_position).normalized()
	attack_target.receive_hit(direction * 1040, damage)

	
	print("Attack")
	pass # Replace with function body.
