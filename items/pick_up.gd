extends RigidBody2D

## Distance at which the item is actually absorbed into the inventory.
const COLLECT_RADIUS := 6.0
## Outer edge of the vacuum. Tiles are 16px and the player moves at 50 units,
## so ~3 tiles reads as a generous magnet without yanking drops across the island.
const VACUUM_RADIUS := 50.0
## Pull speed at the very edge of the vacuum (just under player speed, so it
## reads as "noticed me" rather than an instant snap).
const VACUUM_SPEED_MIN := 40.0
## Pull speed right before collection (~3x player speed, so a walking player
## can never outrun a drop that has already latched on).
const VACUUM_SPEED_MAX := 160.0
## Exponent on the 0..1 closeness factor. >1 keeps the approach lazy at the
## edge and makes the final snap feel accelerated.
const VACUUM_RAMP_EXPONENT := 2.0
## Items aim slightly above the player origin so they vanish into the body,
## not the feet.
const VACUUM_AIM_OFFSET := Vector2(0, -4)

@export var slot_data: SlotData
var shadow: Node2D
var target: Node2D
var delay = false
var run_once = false
@onready var sprite_2d: Sprite2D = $Sprite2D
@onready var area_2d: Area2D = $Area2D
@onready var animation_player: AnimationPlayer = $AnimationPlayer
@onready var sound_manager: SoundManager = _find_sound_manager()


## Was `get_nodes_in_group("SoundManager")[0]`. main.tscn's root node used to be
## declared in that group too, so the index was never a reliable way to reach the
## real manager; the type check is.
func _find_sound_manager() -> SoundManager:
	for node in get_tree().get_nodes_in_group("SoundManager"):
		if node is SoundManager:
			return node
	push_error("PickUp: no SoundManager in the SoundManager group")
	return null


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
	# Magnetism widens the outer edge only; the collection radius stays put so the
	# item still has to reach the player to be absorbed.
	var vacuum_radius: float = VACUUM_RADIUS * PlayerManager.player.stats.pickup_radius_mult

	if distance_to_player <= COLLECT_RADIUS and delay:
		if PlayerManager.player.inventory_data.pick_up_slot_data(slot_data):
			sound_manager.play_sound(sound_manager.SoundType.POP)
			_award_pickup_xp()
			shadow.queue_free()
			queue_free()
		else:
			# Inventory full: leave the drop sitting in the world.
			linear_velocity = Vector2.ZERO
			return
	elif distance_to_player <= vacuum_radius and delay:
		var to_player = PlayerManager.player.global_position - global_position - VACUUM_AIM_OFFSET
		var direction = to_player.normalized()
		# 0 at the edge of the vacuum, 1 at the collection radius.
		var closeness = clampf(
			inverse_lerp(vacuum_radius, COLLECT_RADIUS, distance_to_player), 0.0, 1.0
		)
		var speed = lerpf(VACUUM_SPEED_MIN, VACUUM_SPEED_MAX, pow(closeness, VACUUM_RAMP_EXPONENT))
		linear_velocity = direction * speed
	elif delay:
		linear_velocity = Vector2.ZERO

	
## Vacuuming loot ticks xp, but at a third of a point per drop: see the award table in
## LevelUpManager for why. XP is an integer, so instead of rounding 0.33 down to nothing
## (or up to 1, which would have made hoovering out-earn mining) every PICKUPS_PER_XP-th
## drop pays a whole point. A shared counter rather than a per-drop random roll, so the
## rate is exact and the splash cadence is predictable.
static var _pickups_since_xp := 0


func _award_pickup_xp() -> void:
	_pickups_since_xp += 1
	if _pickups_since_xp < LevelUpManager.PICKUPS_PER_XP:
		return
	_pickups_since_xp = 0

	var level_up_manager := LevelUpManager.find(self)
	if level_up_manager:
		level_up_manager.add_xp(LevelUpManager.XP_PICKUP, global_position)


func _on_body_entered(body: Node2D):
	if not body is Player:
		return
			
	#elif slot_data.item is GameItem:
		#if body.inventory_data.pick_up_slot_data(slot_data):
			#target = body
			

