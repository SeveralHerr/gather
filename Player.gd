extends CharacterBody2D
class_name Player

const SPEED = 300.0
const JUMP_VELOCITY = -400.0

@export var tilemap: TileMapHandler
@export var selectedItemManager: SelectedItemManager
@export var resourceManager: ResourceManager2
@export var items: Items
@export var input_manager: InputManager

var v = Vector2.ZERO

# Get the gravity from the project settings to be synced with RigidBody nodes.
var gravity = ProjectSettings.get_setting("physics/2d/default_gravity")

func _ready():
	add_to_group("SaveLoad")
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
	
	
func _attack():
	$Attack.visible = true
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
	tilemap.set_tile(Vector2i(2, 2), 5, Vector2i(0,0), 1, true)
	tilemap.set_tile(Vector2i(3, 2), 2, Vector2i(0,0), 1, true)

func _move_down():
	v.y += 1
	
func _move_up():
	v.y -= 1
	
func _move_left():
	v.x -= 1
	
func _move_right():
	v.x += 1

func _process_movement():
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
	
