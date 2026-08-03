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

@export var items: Items
var gravity = ProjectSettings.get_setting("physics/2d/default_gravity")
@onready var navigation_agent_2d = $NavigationAgent2D
@onready var los_area_2d = $LineOfSight
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
	# Its own group, so nothing has to find enemies by filtering the save system's
	# membership. mobile_controls.gd used to walk "SaveLoad" and cast each member to Enemy,
	# which worked but coupled a UI file to who happens to persist themselves (gather-xcl).
	add_to_group("Enemy")
	if animated_sprite_2d:
		animated_sprite_2d.play("Idle")
	los_area_2d.connect("body_entered", Callable(self, "_on_body_entered"))
	los_area_2d.connect("body_exited", Callable(self, "_on_body_exited"))
	
	health_manager = HealthManager.new(max_health)
	health_manager.connect("died", Callable(self, "_on_died"))

	for node in get_tree().get_nodes_in_group("Items"):
		if node is Items:
			items = node
			
	# The Camera group scan that used to be here is gone with the `camera` field: shaking now
	# goes through Juice.shake(), which finds and caches the camera once for the whole game
	# rather than once per enemy spawned.
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
	# A kill is the biggest single event in the combat loop and used to be the quietest: the
	# corpse waited 0.2s for its particles and then vanished at full opacity.
	Juice.shake(self, Juice.Shake.HEAVY)
	# The one place hit-stop earns its risk. It is also the case that shaped the design: the
	# trigger node is being freed, so Juice deliberately holds no reference to it and ends the
	# dip on a wall-clock deadline rather than on a timer this node could take down with it.
	Juice.hit_stop(Juice.HIT_STOP_HEAVY)
	_death_pop()

	$HitParticles.emitting = true
	await get_tree().create_timer(0.1).timeout
	$HitParticles.emitting = false
	await get_tree().create_timer(0.1).timeout

	PickUpManager.create_pickup( items.get_item(drop), position)
	drop_loot()
	drop_coins()

	#item_manager.AddItemToWorld(position, items.get_item(drop))
	level_up_manager.add_xp(LevelUpManager.XP_KILL, global_position)
	queue_free()


## Every kill pays at least one coin — gold is the currency land purchase runs on,
## so a zero-coin kill would make combat feel like it paid nothing. Luck (the
## Combat branch's coin_find_bonus) buys a chance at a second one.
const BASE_COIN_DROP := 1


## The type's loot table, on top of `drop` and the coins below.
##
## `drop` stays an @export and stays persisted per enemy: a saved enemy's drop has to come
## back from the save rather than be re-derived from a table that may have changed since. The
## loot table is the part that varies by type and wants to grow — a boss needs several items
## with chances, which a single Types.Item cannot express (gather-33f).
##
## An unregistered item id yields null from get_item(), and create_pickup on null is how the
## whole registry-lookup class of bug starts, so it is skipped with a warning instead.
func drop_loot() -> void:
	for item_type in EnemyRegistry.roll_loot(type):
		var item := items.get_item(item_type)
		if item == null:
			push_warning("Enemy: '%s' loot table names unregistered item %s" % [type, item_type])
			continue
		PickUpManager.create_pickup(item, position)


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
	Juice.shake(self, Juice.Shake.LIGHT)
	GameSoundManager.play_sound(sound)
	$HitParticles.emitting = true
	await get_tree().create_timer(0.1).timeout
	$HitParticles.emitting = false


## Whichever of the two sprite representations this enemy actually has. bone_enemy.tscn has a
## Sprite2D and no AnimatedSprite2D, spider_enemy.tscn the reverse, so every sprite access in
## this file has to ask rather than assume.
func _sprite() -> Node2D:
	return (animated_sprite_2d if animated_sprite_2d else sprite_2d) as Node2D


## Kept so the death pop can kill it. Both animate the sprite's scale, and a killing blow
## starts the squash and the pop within the same call — left to fight, they write the
## property in alternating frames and the corpse flickers instead of swelling.
var _squash_tween: Tween


func add_central_force(force: Vector2):
	knockback = force

	var sprite := _sprite()
	if sprite == null:
		return

	# Stretched along the blow and squashed across it. `knockback` is still never applied to
	# the body — the state machine writes `velocity` every physics frame and would overwrite
	# it — so this squash is what makes a hit read as having moved the enemy at all.
	var squash := Juice.KNOCKBACK_SQUASH
	if absf(force.y) > absf(force.x):
		squash = Vector2(squash.y, squash.x)
	if _squash_tween != null and _squash_tween.is_valid():
		_squash_tween.kill()
	_squash_tween = create_tween()
	_squash_tween.tween_property(sprite, "scale", Vector2.ONE, Juice.KNOCKBACK_SQUASH_TIME) \
		.from(squash).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)

	sprite.material = sprite.material.duplicate()
	sprite.material.set_shader_parameter("flash_intensity", 4)
	await get_tree().create_timer(0.1).timeout
	sprite.material.set_shader_parameter("flash_intensity", 0)


## Swell and fade, over the 0.2s the corpse was already standing there waiting for its
## particles. The node is queue_free()d at the end of that wait and the tween is bound to it,
## so neither outlives the enemy.
func _death_pop() -> void:
	var sprite := _sprite()
	if sprite == null:
		return

	if _squash_tween != null and _squash_tween.is_valid():
		_squash_tween.kill()

	var pop := create_tween()
	pop.set_parallel(true)
	pop.tween_property(sprite, "scale", Vector2.ONE * Juice.DEATH_POP_SCALE, Juice.DEATH_POP_TIME) \
		.set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)
	pop.tween_property(sprite, "modulate:a", 0.0, Juice.DEATH_POP_TIME) \
		.set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_IN)


## AttackTimer has no scene-authored connection any more (gather-1sb). It was wired to a
## handler here whose damage call was commented out and which only printed "Attack" — so
## every enemy in the game ran a no-op and a print on every tick of a timer that
## EnemyAttack and EnemyLunge were separately driving for real. The node itself stays:
## both of those states start it, stop it and connect their own handlers to it.


