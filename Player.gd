extends CharacterBody2D
class_name Player

const SPEED = 300.0
const JUMP_VELOCITY = -400.0
var damage = 3

@export var tilemap: TileMapHandler
@export var selectedItemManager: SelectedItemManager
@export var resourceManager: ResourceManager2
@export var input_manager: InputManager
@export var health_manager: HealthManager
@onready var animation_player = $AnimationPlayer
@onready var attack = $Attack
@onready var animated_sprite_2d = $AnimatedSprite2D
@onready var sound_manager: SoundManager = $"../../SoundManager"
@onready var destroy_manager: DestroyManager = $"../../DestroyManager"
@onready var items: Items = $"../../Items"
@onready var interact: Area2D = $Interact

@onready var camera: Camera = $Camera2D
@onready var area_2d: Area2D = $Area2D
@onready var inventory_manager: InventoryManager = $"../../InventoryManager"
@onready var net = $Net
@onready var hp_bar: ProgressBar = $Camera2D/UI/PlayerInfo/HpBar

@export var inventory_data: InventoryData

var sound_player: AudioStreamPlayer
var sound_player_mining: AudioStreamPlayer
var chest = null

var v = Vector2.ZERO

# Get the gravity from the project settings to be synced with RigidBody nodes.
var gravity = ProjectSettings.get_setting("physics/2d/default_gravity")

func _ready():
	inventory_data = InventoryData.new()
	inventory_data.inventory_slot_datas.append(SlotData.new(GameItems.get_item(Types.Item.Food), 1) as SlotData)
	inventory_data.inventory_slot_datas.append(SlotData.new(GameItems.get_item(Types.Item.IronBar), 9) as SlotData)
	inventory_data.inventory_slot_datas.append(null)
	sound_player = AudioStreamPlayer.new()
	add_child(sound_player)
	sound_player_mining = AudioStreamPlayer.new()
	add_child(sound_player_mining)
	add_to_group("SaveLoad")
	add_to_group("Player")
	$Attack.visible = false
	$Attack.monitoring = false
	health_manager = HealthManager.new(10)
	health_manager.connect("died", Callable(self, "_on_died"))
	hp_bar.max_value = health_manager.max_health
	hp_bar.value = health_manager.current_health

	interact.body_entered.connect(on_interact)
	interact.body_exited.connect(on_interact_exit)

	$AnimatedSprite2D.play("Idle")
	input_manager.connect("move_down", Callable(self, "_move_down"))
	input_manager.connect("move_up", Callable(self, "_move_up"))
	input_manager.connect("move_left", Callable(self, "_move_left"))
	input_manager.connect("move_right", Callable(self, "_move_right"))
	input_manager.connect("mouse_button_left", Callable(self, "_mouse_button_left"))
	input_manager.connect("mouse_button_right", Callable(self, "_mouse_button_right"))
	input_manager.connect("gather_input_press", Callable(self, "_gather_input_press"))
	input_manager.connect("gather_input_release", Callable(self, "_gather_input_release"))
	input_manager.connect("destroy_input_press", Callable(self, "_destroy_input_press"))
	input_manager.connect("destroy_input_release", Callable(self, "_destroy_input_release"))
	input_manager.connect("attack", Callable(self, "_attack"))

	resourceManager.connect("resource_removing", Callable(self, "_on_resource_removing"))
	resourceManager.connect("resource_removing_stop", Callable(self, "_on_resource_removing_stop"))
	attack.connect("body_entered", Callable(self, "_on_body_entered_attack"))

func _on_died():
	print("DEAD")
	
func _on_resource_removing(location: Vector2i, resource):
	#sound_manager.play_sound_queue(sound_manager.SoundType.MINING, sound_player_mining)
	pass
	

func on_interact(body: Node2D):
	chest = body
	pass
	
func on_interact_exit(body: Node2D):
	chest = null
	pass
	
func _on_resource_removing_stop(location: Vector2i, resource):
	#sound_player_mining.stop()
	pass
		
func _destroy_input_release():
	$AnimatedSprite2D.play("Idle")
	$Gather.visible=false
	
	destroy_manager.stop_removing_resource()
	pass
	
func _destroy_input_press():
	$Gather.visible = true
	#$AnimatedSprite2D.play("Gathering")
	if not $AnimatedSprite2D.flip_h:
		$AnimationPlayer.play("Gather")
	else:
		$AnimationPlayer.play("Gather_left")
		
	destroy_manager.start_removing_resource()
	pass	

func receive_hit(force: Vector2, damage: int):
	#velocity += force
	#move_and_slide()
	camera.apply_shake()
	health_manager.take_damage(damage)
	hp_bar.max_value = health_manager.max_health
	hp_bar.value = health_manager.current_health
	animated_sprite_2d.material.set_shader_parameter("flash_intensity", 4)
	animated_sprite_2d.material.set_shader_parameter("r", 1)
	animated_sprite_2d.material.set_shader_parameter("g", 0)
	animated_sprite_2d.material.set_shader_parameter("b", 0)
	await get_tree().create_timer(0.1).timeout
	animated_sprite_2d.material.set_shader_parameter("flash_intensity", 0)
	animated_sprite_2d.material.set_shader_parameter("r", 1)
	animated_sprite_2d.material.set_shader_parameter("g", 1)
	animated_sprite_2d.material.set_shader_parameter("b", 1)
	#sound_manager.play_sound(sound_manager.SoundType.HIT)
	
func set_pickaxe_skin():
	$Gather.texture = selectedItemManager.get_selected_item().get_atlas()

func _on_body_entered_attack(body: Node2D):
	if body is Enemy:
		var direction = (body.global_position - global_position).normalized()
		body.receive_hit(direction * 100, 3)
	
func _attack():
	#v.x = 100
	
	attack.visible = true
	attack.monitoring = true
	if not $AnimatedSprite2D.flip_h:
		$AnimationPlayer.play("Attack")
	else:
		$AnimationPlayer.play("Attack_Left")
	pass
func _gather_input_press():
	#inventory_manager.AddItem(items.get_item(Types.Item.Net), 1)
	var selected_item = selectedItemManager.selected_inventory_slot_item
	if selected_item == null:		
		return
		
	match selected_item.item.type:
		Types.Item.BoneEnemy:
			handle_bone_enemy_interaction()
		Types.Item.Net:
			handle_net_interaction()
		Types.Item.WoodPickaxe:
			handle_pickaxe_interaction()
		Types.Item.IronPickaxe:
			handle_pickaxe_interaction()
		_:
			net.visible = false
			net.monitoring = false
	
func handle_pickaxe_interaction():
	set_pickaxe_skin()
	$Gather.visible = true
	#$AnimatedSprite2D.play("Gathering")
	if not $AnimatedSprite2D.flip_h:
		$AnimationPlayer.play("Gather")
	else:
		$AnimationPlayer.play("Gather_left")

	resourceManager.start_removing_resource(selectedItemManager.get_selected_item().power)
	
func handle_bone_enemy_interaction():
	var nodes = area_2d.get_overlapping_areas()
	var closest_turret = find_closest_object_parent(nodes, BoneTurret)
			

	if closest_turret != null and  closest_turret is BoneTurret:
		closest_turret.set_loaded()
		inventory_manager.RemoveItem(Types.Item.BoneEnemy)

func handle_net_interaction():
	net.visible = true
	net.monitoring = true
	
	if not $AnimatedSprite2D.flip_h:
		animation_player.play("Net_Right")
	else:
		animation_player.play("Net_Left")
	
	var nodes = $LineOfSight.get_overlapping_bodies()
	var closest_enemy = find_closest_object(nodes, Enemy)
			
	if closest_enemy != null and closest_enemy.type == "Bone":
		inventory_manager.AddItem(items.get_item(Types.Item.BoneEnemy), 1)
		inventory_manager.RemoveItem(Types.Item.Net)
		net.visible = false
		net.monitoring = false	
		closest_enemy.queue_free()

func find_closest_object_parent(nodes, type):
	var closest_object = null
	var closest_distance = INF
	for n in nodes:
		var node = n.get_parent()
		if is_instance_of(node, type):
			var distance = global_position.distance_to(node.global_position)
			if distance < closest_distance:
				closest_distance = distance
				closest_object = node
	return closest_object

func find_closest_object(nodes, type):
	var closest_object = null
	var closest_distance = INF
	for node in nodes:
		print(node, type)
		if is_instance_of(node, type):
			var distance = global_position.distance_to(node.global_position)
			if distance < closest_distance:
				closest_distance = distance
				closest_object = node
	return closest_object

func _gather_input_release():

	resourceManager.stop_removing_resource()
	$AnimatedSprite2D.play("Idle")
	$Gather.visible=false

func _mouse_button_left(test: bool):
	#print("left")
	#tilemap.tileMap.set_cell(1, Vector2i(2, 2), -1)
	#tilemap.tileMap.set_cell(1, Vector2i(2, 2), 6, Vector2i(0,0), -1)
	pass

func _mouse_button_right():
	selectedItemManager.ClearSelection()
	#tilemap.tileMap.set_cell(1, Vector2i(2, 2), 3, Vector2i(0,0), 3)
	#tilemap.set_tile(Vector2i(3, 2), 8, Vector2i(0,0), 1, true)
	#tilemap.set_tile_item(Vector2i(3,2), items.get_item(Types.Item.Chest))
	#tilemap.set_tile_item(Vector2(3, 3), items.get_item(Types.Item.WoodDoor))

func _move_down():
	sound_manager.play_sound_queue(sound_manager.SoundType.WALKING, sound_player)
	v.y += 1
	
func _move_up():
	sound_manager.play_sound_queue(sound_manager.SoundType.WALKING, sound_player)
	v.y -= 1
	
func _move_left():
	sound_manager.play_sound_queue(sound_manager.SoundType.WALKING, sound_player)
	v.x -= 1
	
func _move_right():
	sound_manager.play_sound_queue(sound_manager.SoundType.WALKING, sound_player)
	v.x += 1

func _process_movement():
	if v == Vector2.ZERO:
		sound_player.stop()
	
	velocity = v * 50
	v = Vector2.ZERO 
	
	move_and_slide()
	
func _process(delta):
	if Input.is_action_just_pressed("gather"):
		chest.player_interact()
	pass
	
func get_drop_position() -> Vector2:
	var direction = -camera.global_position
	return camera.global_position + direction
	
func _physics_process(delta):
	#$AnimatedSprite2D.play("Idle")
		
	_process_movement()
	
	if not $AnimationPlayer.is_playing():
		$Attack.visible = false
		$Attack.monitoring = false
		net.visible = false
		net.monitorable = false

	if velocity.x != 0:
		$AnimatedSprite2D.flip_v = false
		$AnimatedSprite2D.flip_h = velocity.x < 0


func saveObject() -> Dictionary:
	var dict := {
		"filepath": get_path(),
		"x": position.x,
		"y": position.y,
		"hp": health_manager.current_health
	}
	return dict
	
func loadObject(loadedDict: Dictionary) -> void:
	position = Vector2(loadedDict["x"], loadedDict["y"])
	health_manager.current_health = loadedDict["hp"]
	hp_bar.max_value = health_manager.max_health
	hp_bar.value = health_manager.current_health
	
