extends CharacterBody2D
class_name Player

const SPEED = 300.0
const JUMP_VELOCITY = -400.0

@export var tilemap: TileMapHandler
@export var selectedItemManager: SelectedItemManager
@export var resourceManager: ResourceManager2
@export var items: Items
@export var input_manager: InputManager
@onready var animation_player = $AnimationPlayer
@onready var attack = $Attack
@onready var animated_sprite_2d = $AnimatedSprite2D
@onready var sound_manager: SoundManager = $"../../SoundManager"
var sound_player: AudioStreamPlayer


var v = Vector2.ZERO

# Get the gravity from the project settings to be synced with RigidBody nodes.
var gravity = ProjectSettings.get_setting("physics/2d/default_gravity")

func _ready():
	sound_player = AudioStreamPlayer.new()
	add_child(sound_player)
	add_to_group("SaveLoad")
	add_to_group("Player")
	$AnimatedSprite2D.play("Idle")
	input_manager.connect("move_down", Callable(self, "_move_down"))
	input_manager.connect("move_up", Callable(self, "_move_up"))
	input_manager.connect("move_left", Callable(self, "_move_left"))
	input_manager.connect("move_right", Callable(self, "_move_right"))
	input_manager.connect("mouse_button_left", Callable(self, "_mouse_button_left"))
	input_manager.connect("mouse_button_right", Callable(self, "_mouse_button_right"))
	input_manager.connect("gather_input_press", Callable(self, "_gather_input_press"))
	input_manager.connect("gather_input_release", Callable(self, "_gather_input_release"))
	input_manager.connect("attack", Callable(self, "_attack"))
	attack.connect("body_entered", Callable(self, "_on_body_entered_attack"))
	
func add_central_force(force: Vector2):
	velocity += force
	move_and_slide()
	animated_sprite_2d.material.set_shader_parameter("flash_intensity", 4)
	await get_tree().create_timer(0.1).timeout
	animated_sprite_2d.material.set_shader_parameter("flash_intensity", 0)
	#sound_manager.play_sound(sound_manager.SoundType.HIT)

func _on_body_entered_attack(body: Node2D):
	if body is Enemy:
		var direction = (body.global_position - global_position).normalized()
		body.add_central_force(direction * 1040)
	
func _attack():
	attack.visible = true
	if not $AnimatedSprite2D.flip_h:
		$AnimationPlayer.play("Attack")
	else:
		$AnimationPlayer.play("Attack_Left")
	pass
func _gather_input_press():
	$Gather.visible = true
	#$AnimatedSprite2D.play("Gathering")
	if not $AnimatedSprite2D.flip_h:
		$AnimationPlayer.play("Gather")
	else:
		$AnimationPlayer.play("Gather_left")
	resourceManager.start_removing_resource()
	
func _gather_input_release():
	resourceManager.stop_removing_resource()
	$AnimatedSprite2D.play("Idle")
	$Gather.visible=false

func _mouse_button_left(test: bool):
	pass

func _mouse_button_right():
	selectedItemManager.ClearSelection()
	#tilemap.set_tile(Vector2i(2, 2), 5, Vector2i(0,0), 1, true)
	#tilemap.set_tile(Vector2i(3, 2), 3, Vector2i(0,0), 1, true)
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
	
func _physics_process(delta):
	#$AnimatedSprite2D.play("Idle")
		
	_process_movement()
	
	if not $AnimationPlayer.is_playing():
		$Attack.visible = false

	if velocity.x != 0:
		$AnimatedSprite2D.flip_v = false
		$AnimatedSprite2D.flip_h = velocity.x < 0


func saveObject() -> Dictionary:
	var data 

	var json = {
		"x": position.x,
		"y": position.y
	}
		
	data = JSON.stringify(json)
	
	var dict := {
		"filepath": get_path(),
		"pos": data
	}
	return dict
	
func loadObject(loadedDict: Dictionary) -> void:
	var data = loadedDict.pos
	var json = JSON.new()
	json.parse(data)
	var node = json.get_data()
	position = Vector2(node["x"], node["y"])
	
