extends RigidBody2D

@export var slot_data: SlotData
var shadow: Node2D
var target: Node2D
var delay = false
var run_once = false
@onready var sprite_2d: Sprite2D = $Sprite2D
@onready var area_2d: Area2D = $Area2D
@onready var animation_player: AnimationPlayer = $AnimationPlayer
@onready var sound_manager  =  get_tree().get_nodes_in_group("SoundManager")[0]  
func _ready():
	area_2d.body_entered.connect(_on_body_entered)
	#animation_player.play("Hover")
	await get_tree().create_timer(0.2).timeout
	delay = true
	
	
func _physics_process(_delta):

		
	#var distance_to_shadow =shadow.global_position.distance_to( global_position)
	#await get_tree().create_timer(0.4).timeout
	var distance_to_shadow = shadow.global_position.y - global_position.y
	
	if distance_to_shadow <= 0 and delay and not run_once:
		gravity_scale = 0
		linear_velocity = Vector2.ZERO
		shadow.is_grounded = true
		run_once = true
		
	if not run_once:
		return
		
		
	var distance_to_player = global_position.distance_to(PlayerManager.player.global_position)
	if distance_to_player <= 5 and delay:
		if PlayerManager.player.inventory_data.pick_up_slot_data(slot_data):
			sound_manager.play_sound(sound_manager.SoundType.POP)
			shadow.queue_free()
			queue_free()
		else:
			return
	elif distance_to_player <= 30 and delay:
		var direction = (PlayerManager.player.global_position - global_position - Vector2(0, -4)).normalized()
		#apply_central_impulse(direction * 5 * _delta)
		linear_velocity = direction * 5
	elif delay:
		linear_velocity = Vector2.ZERO

	
func _on_body_entered(body: Node2D):
	if not body is Player:
		return
			
	#elif slot_data.item is GameItem:
		#if body.inventory_data.pick_up_slot_data(slot_data):
			#target = body
			

