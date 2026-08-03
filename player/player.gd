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
@onready var sound_manager: SoundManager = $"../../Systems/SoundManager"
@onready var destroy_manager: DestroyManager = $"../../Systems/DestroyManager"
@onready var items: Items = $"../../Systems/Items"
@onready var interact: Area2D = $Interact
@onready var gather = $Gather
@onready var hot_bar_inventory = $"../../UI/HotBarInventory"
@onready var state_machine: StateMachine = $StateMachine
@onready var gather_state = $StateMachine/PlayerGather
@onready var camera: Camera = $Camera2D
@onready var area_2d: Area2D = $Area2D
@onready var hp_bar: ProgressBar = $Camera2D/HUD/PlayerInfo/HpBar

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
	# Pull the skill totals in case LevelUpManager readied first and found no
	# PlayerManager.player to push them into. It no longer does — it sits in Systems,
	# which main.tscn declares after World — so this loop is now usually a no-op and
	# LevelUpManager._ready() does the push. Both are kept: together they hold
	# whichever way a future edit reorders those two branches.
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
		tilemap.set_interact_highlight(nearest_chest.position)
	pass

func on_interact_exit(body: Node2D):
	chests.erase(body)

	if chests.size() == 0:
		nearest_chest = null
		# Only this system's own cell. remove_highlight() wipes the whole of layer 3,
		# which is also where the gather selector lives (gather-3zg.6).
		tilemap.clear_interact_highlight()

	if nearest_chest:
		tilemap.set_interact_highlight(nearest_chest.position)
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
	# Was a bare `apply_shake()`, i.e. the same one-pixel jitter a pebble breaking asked for.
	# Taking damage is the heaviest thing that happens to the player, so it now says so.
	Juice.shake(self, Juice.Shake.HEAVY)
	# Short — this fires while something is chasing the player, and a long dip while being
	# chased is a punishment on top of the damage rather than feedback about it.
	Juice.hit_stop(Juice.HIT_STOP_LIGHT)
	# Screen space: goes in the UI CanvasLayer, NOT under Camera2D/HUD, which is world-space
	# at the camera's zoom and would draw the "full-screen" rect onto the ground.
	ScreenFlash.flash(self, Juice.DAMAGE_FLASH_COLOR, Juice.DAMAGE_FLASH_ALPHA, Juice.DAMAGE_FLASH_TIME)
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
	# The second of the two independent hit-stop tickers (the other is world/camera.gd). Two,
	# because Engine.time_scale is global and a stuck one has no in-game way out: neither node
	# being freed, disabled or having its processing turned off can strand the clock. It is a
	# bool test while no dip is running. See the hit-stop section of systems/juice.gd.
	Juice.tick()

	if Input.is_action_just_pressed("action"):
		if not nearest_chest:
			return

		if nearest_chest is TestChest:
			nearest_chest.player_interact()

		elif nearest_chest is CraftingStation:
			nearest_chest.player_interact()
			
	# A chest freed while still inside the Interact area never fires body_exited, so `chests`
	# can hold a freed object. Reading .position off one errors every frame; dropping them
	# here is what keeps nearest_chest honest (gather-3zg.6).
	var live_chests: Array = []
	for chest in chests:
		if is_instance_valid(chest):
			live_chests.append(chest)
	if live_chests.size() != chests.size():
		chests = live_chests
		if not is_instance_valid(nearest_chest):
			nearest_chest = null
			tilemap.clear_interact_highlight()

	var nearestDistance = 1000000
	for i in chests.size():
		var tilePos = tilemap.tileMap.local_to_map(chests[i].position)
		var direction = global_position - tilemap.tileMap.map_to_local(tilePos)
		var distance = direction.length()
		if distance < nearestDistance:
			nearestDistance = distance
			nearest_chest = chests[i]
	if nearest_chest:
		# set_interact_highlight is idempotent, so the common case — same chest, same cell —
		# is a comparison rather than a wipe-and-restamp of the whole layer every frame.
		tilemap.set_interact_highlight(nearest_chest.position)
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


# ============================ Save payload ============================
#
# SaveLoad JSON-stringifies whatever saveObject() returns, so nested dictionaries and
# arrays already survive the trip. Every slot used to be JSON.stringify()-ed on its own
# first and re-parsed with a fresh JSON.new() per slot on the way back in — an entire
# encode/decode layer inside a format that did not need one, and one more place for a
# parse to fail without saying so.
#
# The four functions below are static and take plain values because Player is
# scene-backed: half its @onready fields reach up into ../../Systems and ../../UI, so a
# headless test cannot stand one up, and the payload shape is exactly the part worth
# pinning. saveObject()/loadObject() are the thin wrappers SaveLoad calls.

## Sentinel an old save wrote in place of an empty slot. Both fields carried it.
##
## The old shape had no way to say "nothing here": every entry had to be a JSON string,
## and a stringified null parses back to a value the loader then indexed. So emptiness
## was encoded out of band, and what it bought was positional — slot 5 comes back as
## slot 5 rather than the inventory closing up around the gaps. A real null keeps that
## (JSON arrays hold nulls), so that is what the new shape writes; the sentinel is still
## recognised on the way in, forever, because old saves still contain it.
const EMPTY_SLOT_SENTINEL := 1337


func saveObject() -> Dictionary:
	return build_payload(
		str(get_path()), position, health_manager.current_health, inventory_data.inventory_slot_datas
	)


## The dictionary handed to SaveLoad. `slot_datas` is the raw inventory array: a SlotData
## or null per slot.
static func build_payload(filepath: String, pos: Vector2, hp: int, slot_datas: Array) -> Dictionary:
	var inv := []
	for slot_data in slot_datas:
		# `slot_data.item == null` is the second half and it is not defensive padding. This
		# was `if not item:`, which is false for a live SlotData holding a null item, so the
		# else branch dereferenced item.item.type and raised. saveObject() is typed
		# `-> Dictionary`, and a GDScript method that raises still returns its type's default,
		# so SaveLoad was handed a bare {} — a blank line in saveFile, and the player's
		# position, health AND whole inventory gone without a word. Same shape as the bug at
		# items/pick_up_manager.gd:98-102. An item-less slot is an empty slot.
		if slot_data == null or slot_data.item == null:
			inv.append(null)
		else:
			inv.append({"type": slot_data.item.type, "count": slot_data.count})

	return {
		"filepath": filepath,
		# NEVER let this become the bare pair "x" and "y" at the top level. save_load.gd's
		# _load() routes every entry that has both into the position-keyed SaveChunks bucket
		# instead of calling loadObject() on the node (search it for `has("x") and has("y")`),
		# so a flattened position would stop the player entry ever being loaded again —
		# silently, for every save, forever. The "px"/"py" this replaces was buying exactly
		# that separation; one nested key buys it the same way. Anything but that pair is
		# safe: a prefix, or a sub-dictionary like this one.
		#
		# from_native round-trips the Vector2 as a Vector2 rather than leaving the reader to
		# remember which two loose floats belonged together (it writes
		# {"type": "Vector2", "args": [x, y]}). The second argument, full_objects, is left at
		# its default of false and must stay false: with it on, a save file can name a script
		# and have the loader instantiate it, which turns a player-editable file into
		# arbitrary code execution. The same rule applies to to_native() below.
		"pos": JSON.from_native(pos),
		"hp": hp,
		# Still keyed "inv_json" although the entries are no longer JSON text. This is a
		# persistence key: renaming it would mean every save written before this change
		# comes back with an empty inventory, which is the failure this codebase keeps
		# LEGACY_PATHS around for. read_slot() tells the shapes apart by the entries
		# themselves instead.
		"inv_json": inv,
	}


func loadObject(loadedDict: Dictionary) -> void:
	position = read_position(loadedDict, position)
	health_manager.current_health = int(loadedDict.get("hp", health_manager.max_health))
	hp_bar.max_value = health_manager.max_health
	hp_bar.value = health_manager.current_health

	inventory_data.inventory_slot_datas = []
	for slot in read_slots(loadedDict):
		if slot == null:
			inventory_data.inventory_slot_datas.append(null)
			continue

		# items.gd:92 get_item() indexes item_list directly and raises on a type it has no
		# entry for — a save written by a build that had one more item registered, say. The
		# inventory has already been emptied two lines up, so a raise here would abort
		# loadObject() and leave the player holding nothing at all. Checking first costs one
		# lookup and turns that into a single lost slot.
		var item_type: int = int(slot["type"])
		if not GameItems.item_list.has(item_type):
			push_warning("Player: save holds unregistered item type %d, that slot was left empty" % item_type)
			inventory_data.inventory_slot_datas.append(null)
			continue

		inventory_data.inventory_slot_datas.append(
			SlotData.new(GameItems.get_item(item_type), int(slot["count"]))
		)
	inventory_data.inv_updated()


## The saved position, from either shape.
##
## `fallback` is what an entry carrying no position at all resolves to. loadObject()
## passes the player's current position, so a truncated save leaves them standing where
## they are instead of at the world origin — the exact symptom this project's save
## documentation warns about, and one nobody reads as an error when they see it.
static func read_position(payload: Dictionary, fallback: Vector2 = Vector2.ZERO) -> Vector2:
	if payload.has("pos"):
		# Checked before to_native() rather than after: handed something that is not a
		# from_native envelope it raises an engine error, and a hand-edited save is an
		# expected input here.
		var raw: Variant = payload["pos"]
		if raw is Dictionary:
			var native: Variant = JSON.to_native(raw)
			if native is Vector2:
				return native
		push_warning("Player: save entry has an unreadable 'pos', falling back to px/py")

	# Old shape: the position was hand-split into two loose floats.
	if payload.has("px") and payload.has("py"):
		return Vector2(float(payload["px"]), float(payload["py"]))

	push_warning("Player: save entry carries no position, the player was left where it was")
	return fallback


## The saved inventory, normalised to one entry per slot: null for an empty slot, or
## {"type": int, "count": int}.
static func read_slots(payload: Dictionary) -> Array:
	var out := []

	if not payload.has("inv_json"):
		push_warning("Player: save entry carries no inventory, none was restored")
		return out

	var saved: Variant = payload["inv_json"]
	if saved is not Array:
		push_warning("Player: save entry's inventory is not an array, none was restored")
		return out

	for entry in saved:
		out.append(read_slot(entry))
	return out


## One saved slot, from either shape. Returns null for an empty slot and for anything
## unreadable — a slot that cannot be understood is better left empty than left to
## abort the load half-way through the inventory.
static func read_slot(entry: Variant) -> Variant:
	var slot: Variant = entry

	# The new shape's empty slot, and the only silent way out below: everything else that
	# fails to resolve warns, because it means a save came back holding less than it stored.
	if slot == null:
		return null

	# THE structural test for an old save, and deliberately the only one. An old entry is
	# a String holding the slot's JSON; a new one is the dictionary itself. A save-format
	# version number would answer the same question, but coupling to one would mean this
	# change and the version header could only ever land together.
	if slot is String:
		# JSON.new().parse() and its return code rather than the static JSON.parse_string():
		# parse() hands the failure back, parse_string() pushes an engine error to stderr.
		# saveFile is a plain text file a player can edit, so a malformed line is an expected
		# input to handle, not an engine fault to shout about. Matches enemy_spawner.gd:262
		# and island_manager.gd.
		var reader := JSON.new()
		if reader.parse(str(slot)) != OK:
			push_warning("Player: unparseable inventory slot in save, restored as empty")
			return null
		slot = reader.get_data()

	if slot is not Dictionary:
		push_warning("Player: inventory slot in save is not a dictionary, restored as empty")
		return null
	if not slot.has("type") or not slot.has("count"):
		push_warning("Player: inventory slot in save has no type/count, restored as empty")
		return null
	if int(slot["type"]) == EMPTY_SLOT_SENTINEL and int(slot["count"]) == EMPTY_SLOT_SENTINEL:
		return null

	# JSON has one number type, so everything comes back a float. The item type is an
	# enum and the count is a stack size; both are ints on the way in and on the way out.
	return {"type": int(slot["type"]), "count": int(slot["count"])}

