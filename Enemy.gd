extends CharacterBody2D


const SPEED = 300.0
const JUMP_VELOCITY = -400.0

@export var target: Node2D

# Get the gravity from the project settings to be synced with RigidBody nodes.
var gravity = ProjectSettings.get_setting("physics/2d/default_gravity")
@onready var navigation_agent_2d = $NavigationAgent2D


func _physics_process(delta):
	# Add the gravity.
	var direction = to_local(navigation_agent_2d.get_next_path_position()).normalized()
	velocity = direction * 10
	
	move_and_slide()
	
func create_path():
	navigation_agent_2d.target_position = target.global_position
	pass
	
	

func _on_timer_timeout():
	create_path()
	pass # Replace with function body.
