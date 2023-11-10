extends CharacterBody2D
class_name Player

const SPEED = 300.0
const JUMP_VELOCITY = -400.0

@export var tilemap: TileMapHandler
@export var selectedItemManager: SelectedItemManager

# Get the gravity from the project settings to be synced with RigidBody nodes.
var gravity = ProjectSettings.get_setting("physics/2d/default_gravity")


func _physics_process(delta):
	var v = Vector2.ZERO # The player's movement vector.
	if Input.is_action_pressed(&"move_right"):
		v.x += 1
	if Input.is_action_pressed(&"move_left"):
		v.x -= 1
	if Input.is_action_pressed(&"move_down"):
		v.y += 1
	if Input.is_action_pressed(&"move_up"):
		v.y -= 1
	if Input.is_mouse_button_pressed(MOUSE_BUTTON_RIGHT):
		selectedItemManager.ClearSelection()
	if Input.is_mouse_button_pressed(MOUSE_BUTTON_LEFT):
		#selectedItemManager.Place()
		pass
	if Input.is_action_just_pressed("gather"):
		$AnimatedSprite2D.play("Gathering")
		tilemap.RemoveNearestResourceToPlayer()
	else: 
		$AnimatedSprite2D.play("Idle")
		
	# Apply gravity
	velocity = v * 50
	
	# Move the character and handle collision
	move_and_slide()

	if velocity.x != 0:
		$AnimatedSprite2D.flip_v = false
		$AnimatedSprite2D.flip_h = velocity.x < 0
