extends CharacterBody2D
class_name Enemy

const SPEED = 300.0
const JUMP_VELOCITY = -400.0

@export var target: Player
@export var attack_target: Player

var health_manager: HealthManager

## Both exported so an enemy is data rather than a shape baked into this script. They used
## to be a literal 10 in _ready and a literal 3 in EnemyAttack, which meant every enemy in
## the game was exactly as tough as every other one and the boss island had nothing to put
## on it. Set them before add_child(): _ready is what builds the HealthManager.
@export var max_health := 10
@export var damage = 3
var camera: Camera

@export var items: Items
var gravity = ProjectSettings.get_setting("physics/2d/default_gravity")
@onready var navigation_agent_2d = $NavigationAgent2D
@onready var los_area_2d = $LineOfSight
@onready var player =  get_tree().get_nodes_in_group("Player")[0]  
@onready var soft_collision = $SoftCollision
@onready var collision = $CollisionShape2D2
@onready var attack_range : Area2D = $AttackRange
@onready var sprite_2d = get_node_or_null("Sprite2D")
@onready var attack_timer = $AttackTimer
@onready var animated_sprite_2d: AnimatedSprite2D = get_node_or_null("AnimatedSprite2D") as AnimatedSprite2D
@export var type: String = ""
@export var drop: Types.Item
@export var sound: GameSoundManager.SoundType

var level_up_manager: LevelUpManager

var detection_range = 100
var speed = 10
var knockback = Vector2.ZERO

var raycast: RayCast2D

var lunge_speed = 500    # Speed of the lunge
var lunge_distance = 18 # Distance at which the enemy starts lunging
var normal_speed = 10   # Normal speed
var cooldown_time = 1.0 # Time in seconds between lunges
var in_cooldown = false
var is_lunging = false
var anticipation_time = 0.5
var lunge_time = 1

func _ready():
	add_to_group("SaveLoad")
	if animated_sprite_2d:
		animated_sprite_2d.play("Idle")
	los_area_2d.connect("body_entered", Callable(self, "_on_body_entered"))
	los_area_2d.connect("body_exited", Callable(self, "_on_body_exited"))
	
	health_manager = HealthManager.new(max_health)
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
	drop_coins()

	#item_manager.AddItemToWorld(position, items.get_item(drop))
	level_up_manager.add_xp(LevelUpManager.XP_KILL, global_position)
	queue_free()


## Every kill pays at least one coin — gold is the currency land purchase runs on,
## so a zero-coin kill would make combat feel like it paid nothing. Luck (the
## Combat branch's coin_find_bonus) buys a chance at a second one.
const BASE_COIN_DROP := 1


func drop_coins() -> void:
	var coins := BASE_COIN_DROP

	var p = PlayerManager.player
	if p != null and p.stats != null and randf() < p.stats.coin_find_bonus:
		coins += 1

	for _i in coins:
		PickUpManager.create_pickup(items.get_item(Types.Item.Coin), position)


func _on_body_entered(body: Node2D):
	if body is Player:
		target = body

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

func _physics_process(_delta):
	move_and_slide()

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
	# Spawn before the awaits below: the number lives in a world-level container,
	# so it survives (and cleans up after) this enemy dying from the same hit.
	DamageNumber.spawn(self, global_position, _damage)
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
	#attack_target.receive_hit(direction * 1040, damage)

	
	print("Attack")
	pass # Replace with function body.


