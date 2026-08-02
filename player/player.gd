extends CharacterBody2D
class_name Player

const SPEED = 300.0
const JUMP_VELOCITY = -400.0

## Walk speed before the Light Step multiplier.
const MOVE_SPEED := 50.0
## Health before the Tough Hide bonus.
const BASE_MAX_HEALTH := 10

var damage = 3

## Totals contributed by the skill tree. Built as a field initializer rather than
## in _ready() because _ready() runs child-first: ResourceManager2 and the pickup
## vacuum both read stats off the player before the Player's own _ready() has run.
var stats := PlayerStats.new()

@export var tilemap: TileMapHandler
@export var resourceManager: ResourceManager2
@export var input_manager: InputManager
var health_manager: HealthManager
@onready var animation_player = $AnimationPlayer
@onready var attack = $Attack
@onready var net = $Net
@onready var attack_sprite: Sprite2D = $Attack/Sprite
@onready var animated_sprite_2d = $AnimatedSprite2D
@onready var line_of_sight = $LineOfSight
@onready var sound_manager: SoundManager = $"../../SoundManager"
@onready var destroy_manager: DestroyManager = $"../../DestroyManager"
@onready var items: Items = $"../../Items"
@onready var interact: Area2D = $Interact
@onready var gather = $Gather
@onready var hot_bar_inventory = $"../../UI2/HotBarInventory"
@onready var state_machine: StateMachine = $StateMachine
@onready var gather_state = $StateMachine/PlayerGather
@onready var camera: Camera = $Camera2D
@onready var area_2d: Area2D = $Area2D
@onready var hp_bar: ProgressBar = $Camera2D/UI/PlayerInfo/HpBar

@export var inventory_data: InventoryData

const RESPAWN_INVULNERABLE_TIME := 2.0

var sound_player: AudioStreamPlayer
var sound_player_mining: AudioStreamPlayer
var chests = []
var nearest_chest = null
var v = Vector2.ZERO

# Where a death sends the player back to. main.gd overwrites this once the island
# has been generated and it knows which tile the player was dropped on.
var spawn_position: Vector2
var is_dead := false
var invulnerable := false

# Separate from `invulnerable` on purpose. That flag is owned by the respawn
# sequence: _grant_invulnerability() sets it, waits, then clears it, so anything
# that writes it from outside is silently undone the next time the player dies.
# This one is only ever written by the debug panel and nothing in the game clears
# it, which is what makes it a toggle rather than a timer.
var god_mode := false

# Get the gravity from the project settings to be synced with RigidBody nodes.
var gravity = ProjectSettings.get_setting("physics/2d/default_gravity")

func _ready():
	# VISIBLE, not CAPTURED, and it is load-bearing for the whole HUD.
	#
	# CAPTURED locks the pointer to the middle of the window and hides it, and Godot
	# picks no Control while it is set — so every button the game draws was
	# unclickable. That is why hot_bar_inventory.gd calls its own < / > buttons
	# "decoration" and grew Q / E to work around them, and it is why the skill tree
	# and the land panel had no on-screen way in at all (ui/hud_toolbar.gd).
	#
	# Nothing here ever wanted the capture: no aiming reads the cursor. Gathering,
	# placing and attacking all resolve against the tile the player faces, and the
	# panels used to hand the cursor back on open precisely because they needed it.
	# Those handshakes are gone now — the cursor is simply always free.
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE

	inventory_data = InventoryData.new()
	inventory_data.inventory_slot_datas.append(SlotData.new(GameItems.get_item(Types.Item.WoodPickaxe), 1) as SlotData)
	inventory_data.inventory_slot_datas.append(SlotData.new(GameItems.get_item(Types.Item.Sword), 1) as SlotData)
	inventory_data.inventory_slot_datas.append(SlotData.new(GameItems.get_item(Types.Item.Sawmill), 1) as SlotData)
	inventory_data.inventory_slot_datas.append(null)
	inventory_data.inventory_slot_datas.append(null)
	inventory_data.inventory_slot_datas.append(null)
	inventory_data.inventory_slot_datas.append(null)

	inventory_data.inventory_slot_datas.append(null)
	inventory_data.inventory_slot_datas.append(null)
	inventory_data.inventory_slot_datas.append(null)
	inventory_data.inventory_slot_datas.append(null)
	inventory_data.inventory_slot_datas.append(null)
	sound_player = AudioStreamPlayer.new()
	add_child(sound_player)
	sound_player_mining = AudioStreamPlayer.new()
	add_child(sound_player_mining)
	add_to_group("SaveLoad")
	add_to_group("Player")
	$Attack.visible = false
	$Attack.monitoring = false
	health_manager = HealthManager.new(BASE_MAX_HEALTH)
	health_manager.connect("died", Callable(self, "_on_died"))
	hp_bar.max_value = health_manager.max_health
	hp_bar.value = health_manager.current_health
	spawn_position = position
	PlayerManager.player = self

	stats.stats_changed.connect(_on_stats_changed)
	# LevelUpManager is a descendant of this node, so its _ready() has already run
	# and found no PlayerManager.player to push totals into. Pull them now.
	for node in get_tree().get_nodes_in_group("LevelUpManager"):
		if node is LevelUpManager:
			node.sync_player_stats()
	interact.body_entered.connect(on_interact)
	interact.body_exited.connect(on_interact_exit)

	$AnimatedSprite2D.play("Idle")
	input_manager.connect("move_down", Callable(self, "_move_down"))
	input_manager.connect("move_up", Callable(self, "_move_up"))
	input_manager.connect("move_left", Callable(self, "_move_left"))
	input_manager.connect("move_right", Callable(self, "_move_right"))
	# _mouse_button_left, _mouse_button_right and _gather_input_press were connected here
	# too. None of the three has ever existed on this class, so Object.connect rejected
	# the callable and logged an error at every boot — noise in the one log that carries
	# this project's real failure signal. Nothing regressed by removing them: the gather
	# press reaches the game through HotBarInventory (hot_bar_inventory.gd:39), and
	# mouse_button_left is consumed by main.gd:54.
	input_manager.connect("gather_input_release", Callable(self, "_gather_input_release"))
	input_manager.connect("destroy_input_press", Callable(self, "_destroy_input_press"))
	input_manager.connect("destroy_input_release", Callable(self, "_destroy_input_release"))
	input_manager.connect("attack", Callable(self, "_attack"))

	resourceManager.connect("resource_removing", Callable(self, "_on_resource_removing"))
	resourceManager.connect("resource_removing_stop", Callable(self, "_on_resource_removing_stop"))
	attack.connect("body_entered", Callable(self, "_on_body_entered_attack"))
	


func set_spawn_position(new_spawn: Vector2) -> void:
	spawn_position = new_spawn


func _on_died():
	if is_dead:
		return
	is_dead = true
	respawn()


# Forager-style: death costs you the trip back, not your inventory. Full heal at the
# spawn point plus a grace window so the enemy that killed you cannot immediately
# kill you again while you are still standing in its lap.
func respawn() -> void:
	input_manager.disable_input = true
	animation_player.stop()
	gather.visible = false
	$Attack.visible = false
	$Attack.monitoring = false

	await get_tree().create_timer(0.5).timeout

	position = spawn_position
	velocity = Vector2.ZERO
	v = Vector2.ZERO
	health_manager.reset_health()
	update_hp_bar()

	is_dead = false
	input_manager.disable_input = false
	_grant_invulnerability(RESPAWN_INVULNERABLE_TIME)


func _grant_invulnerability(duration: float) -> void:
	invulnerable = true
	var blink := create_tween()
	blink.set_loops(int(duration / 0.2))
	blink.tween_property(animated_sprite_2d, "modulate:a", 0.3, 0.1)
	blink.tween_property(animated_sprite_2d, "modulate:a", 1.0, 0.1)
	await get_tree().create_timer(duration).timeout
	blink.kill()
	animated_sprite_2d.modulate.a = 1.0
	invulnerable = false


func update_hp_bar() -> void:
	hp_bar.max_value = health_manager.max_health
	hp_bar.value = health_manager.current_health


# Max health is the only stat that has to be pushed somewhere on change; the rest
# are read at the point of use.
func _on_stats_changed() -> void:
	if health_manager == null:
		return

	health_manager.set_max_health(BASE_MAX_HEALTH + stats.max_health_bonus)
	update_hp_bar()



func _on_resource_removing(_location: Vector2i, _resource):
	#sound_manager.play_sound_queue(sound_manager.SoundType.MINING, sound_player_mining)
	pass
	

func on_interact(body: Node2D):
	if not chests.has(body):
		chests.append(body)
		
	if nearest_chest:
		tilemap.add_highlight(nearest_chest.position)	
	pass
	
func on_interact_exit(body: Node2D):
	chests.erase(body)
			
	if chests.size() == 0:
		nearest_chest = null
		tilemap.remove_highlight()
			
	if nearest_chest:
		tilemap.remove_highlight()
		tilemap.add_highlight(nearest_chest.position)	
	pass
	
func is_facing_left():
	return animated_sprite_2d.flip_h

	
func _on_resource_removing_stop(_location: Vector2i, _resource):
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

func receive_hit(_force: Vector2, _damage: int):
	if is_dead or invulnerable or god_mode:
		return

	#velocity += force
	#move_and_slide()
	camera.apply_shake()
	health_manager.take_damage(_damage)
	update_hp_bar()
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

func _on_body_entered_attack(body: Node2D):
	if body is Enemy:
		var direction = (body.global_position - global_position).normalized()
		# The equipped sword sets `damage` (PlayerManager.show_slot_data); this used
		# to pass a hardcoded 3, so neither the sword nor any skill reached the enemy.
		body.receive_hit(direction * 100, damage + stats.damage_bonus)
	
func _attack():
	if is_dead:
		return
	state_machine.change_to("PlayerAttack")

func _gather_input_release():
	#$StateMachine.change_to("PlayerIdle")
	resourceManager.stop_removing_resource()
	#$AnimatedSprite2D.play("Idle")
	#$Gather.visible=false
	animation_player.stop()

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
	
	velocity = v * MOVE_SPEED * stats.move_speed_mult
	v = Vector2.ZERO
	
	move_and_slide()
	
func _process(_delta):		
	
	if Input.is_action_just_pressed("action"):
		if not nearest_chest:
			return

		if nearest_chest is TestChest:
			nearest_chest.player_interact()

		elif nearest_chest is CraftingStation:
			nearest_chest.player_interact()
			
	var nearestDistance = 1000000
	for i in chests.size():
		var tilePos = tilemap.tileMap.local_to_map(chests[i].position)
		var direction = global_position - tilemap.tileMap.map_to_local(tilePos)
		var distance = direction.length()
		if distance < nearestDistance:
			nearestDistance = distance
			nearest_chest = chests[i]
	if nearest_chest:
		tilemap.remove_highlight()
		tilemap.add_highlight(nearest_chest.position)	
	pass
	
func get_drop_position() -> Vector2:
	var direction = -camera.global_position
	return camera.global_position + direction
	
func _physics_process(_delta):
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
	var inv = []
	for i in inventory_data.inventory_slot_datas.size():
		var item = inventory_data.inventory_slot_datas[i]
		
		var json 
		if not item:
			json = {
				"type": 1337,
				"count": 1337
			}
		else:
			json = {
				"type": item.item.type,
				"count": item.count
			}

		inv.append(JSON.stringify(json))
		
	var dict := {
		"filepath": get_path(),
		"px": position.x,
		"py": position.y,
		"hp": health_manager.current_health,
		"inv_json": inv
	}
	return dict
	
func loadObject(loadedDict: Dictionary) -> void:
	position = Vector2(loadedDict["px"], loadedDict["py"])
	health_manager.current_health = loadedDict["hp"]
	hp_bar.max_value = health_manager.max_health
	hp_bar.value = health_manager.current_health
	
	inventory_data.inventory_slot_datas = []
	for i in loadedDict.inv_json.size():
		var saved_info = loadedDict.inv_json[i]
		var json = JSON.new()
		json.parse(saved_info)
		var node = json.get_data()
		
		if node["type"] == 1337 and node["count"] == 1337:
			inventory_data.inventory_slot_datas.append(null)
		else:
			inventory_data.inventory_slot_datas.append(SlotData.new(GameItems.get_item(node["type"]), node["count"]))
	inventory_data.inv_updated()
	
