extends CharacterBody2D
class_name Enemy

const SPEED = 300.0
const JUMP_VELOCITY = -400.0

@export var target: Player
@export var attack_target: Player

@export var health_manager: HealthManager
@export var damage = 3
var camera: Camera

@export var items: Items
var gravity = ProjectSettings.get_setting("physics/2d/default_gravity")
@onready var navigation_agent_2d = $NavigationAgent2D
@onready var los_area_2d = $LineOfSight
@onready var player =  get_tree().get_nodes_in_group("Player")[1]  
@onready var soft_collision = $SoftCollision
@onready var attack_range = $AttackRange
@onready var sprite_2d = $Sprite2D
@onready var animated_sprite_2d: AnimatedSprite2D = $AnimatedSprite2D
@export var type: String = ""
@export var drop: Types.Item
@export var sound: GameSoundManager.SoundType

var level_up_manager: LevelUpManager

var detection_range = 100
var speed = 10
var knockback = Vector2.ZERO

var raycast: RayCast2D

var lunge_speed = 50    # Speed of the lunge
var lunge_distance = 18 # Distance at which the enemy starts lunging
var normal_speed = 10   # Normal speed
var cooldown_time = 1.0 # Time in seconds between lunges
var in_cooldown = false

func _ready():
	add_to_group("SaveLoad")
	if animated_sprite_2d:
		animated_sprite_2d.play("Idle")
	los_area_2d.connect("body_entered", Callable(self, "_on_body_entered"))
	los_area_2d.connect("body_exited", Callable(self, "_on_body_exited"))
	
	health_manager = HealthManager.new(10)
	health_manager.connect("died", Callable(self, "_on_died"))

	for node in get_tree().get_nodes_in_group("Items"):
		if node is Items:
			items = node
			
	for node in get_tree().get_nodes_in_group("Camera"):
		if node is Camera:
			camera = node
			
	for node in get_tree().get_nodes_in_group("LevelUpManager"):
		if node is LevelUpManager:
			level_up_manager = node 
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
	
	PickUpManager.create_pickup( items.get_item(drop), position)
	
	#item_manager.AddItemToWorld(position, items.get_item(drop))
	level_up_manager.add_xp(5)
	queue_free()


func _on_body_entered(body: Node2D):
	if body is Player:
		target = body

func _on_player_detected():
	print("Player detected!")

func _on_body_exited(body: Node2D):
	if animated_sprite_2d:
		animated_sprite_2d.play("Idle")
	if body is Player:
		target = null
	
func _on_body_attack_entered(body: Node2D):
	if body is Player:
		attack_target = body


func _on_body_attack_exited(body: Node2D):
	if body is Player:
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


func _physics_process(delta):
	if target == null:
		return

	var distance = position.distance_to(player.position)
	var current_speed = normal_speed
	
	if distance <= lunge_distance and not in_cooldown:
		current_speed = lunge_speed
		await get_tree().create_timer(cooldown_time).timeout
		in_cooldown = false

	if animated_sprite_2d:
		animated_sprite_2d.play("Walking")

	var direction = to_local(navigation_agent_2d.get_next_path_position()).normalized()
	velocity = direction * current_speed + knockback
	
	if soft_collision.is_colliding():
		velocity += soft_collision.get_push_vector() * delta * 400
	
	move_and_collide(velocity * delta)
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

	return nearest_object
		
func receive_hit(force: Vector2, _damage: int):
	add_central_force(force)
	health_manager.take_damage(_damage)
	camera.apply_shake(1)
	GameSoundManager.play_sound(sound)
	$HitParticles.emitting = true
	await get_tree().create_timer(0.1).timeout
	$HitParticles.emitting = false
func add_central_force(force: Vector2):
	knockback = force

	var sprite
	if animated_sprite_2d:
		sprite = animated_sprite_2d
	else:
		sprite = sprite_2d


	sprite.material = sprite.material.duplicate()
	sprite.material.set_shader_parameter("flash_intensity", 4)
	await get_tree().create_timer(0.1).timeout
	sprite.material.set_shader_parameter("flash_intensity", 0)


func _on_attack_timer_timeout():
	if attack_target == null:
		return
		
	var direction = (attack_target.global_position - global_position).normalized()
	attack_target.receive_hit(direction * 1040, damage)

	
	print("Attack")
	pass # Replace with function body.


