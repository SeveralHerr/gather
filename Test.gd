extends CharacterBody2D

@export var movement_speed: float = 4.0
@export var navigation_agent: NavigationAgent2D 
@export var tile_map_handler: TileMapHandler
@export var player: Player
var movement_delta: float

func _ready() -> void:
	navigation_agent.target_position = player.global_position
	pass



func _physics_process(delta):


	var dir = to_local(navigation_agent.get_next_path_position()).normalized()
	velocity = dir * delta
	move_and_slide()
	


func _on_timer_timeout():
	navigation_agent.target_position = player.global_position
