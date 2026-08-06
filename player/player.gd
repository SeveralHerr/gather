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
## Typed, unlike `gather_state` above, because `_dodge()` asks it `can_roll()` before
## transitioning rather than after — see PlayerRoll.can_roll() for why that ordering matters.
@onready var roll_state: PlayerRoll = $StateMachine/PlayerRoll
@onready var camera: Camera = $Camera2D
@onready var area_2d: Area2D = $Area2D
@onready var hp_bar: ProgressBar = $Camera2D/HUD/PlayerInfo/HpBar

@export var inventory_data: InventoryData

const RESPAWN_INVULNERABLE_TIME := 2.0

var sound_player: AudioStreamPlayer
var sound_player_mining: AudioStreamPlayer

# Every body currently inside the Interact area, interactable or not. The name predates
# crafting stations and is kept because it is threaded through four methods; what it actually
# holds is "things in reach". Which of them can be OPENED is InteractPrompt.is_interactable's
# answer, asked in _process — see there for why that predicate is duck-typed.
var chests = []
var nearest_chest = null

## The world-space "F / Furnace" bubble over `nearest_chest` (`ui/interact_prompt.gd`).
## Created here rather than authored into main.tscn for the same reason GatherProgress is
## created by ResourceManager2: it belongs beside the thing it points at, it is one shared
## instance reused for every interactable in the game, and nothing about it is saved.
var interact_prompt: InteractPrompt

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

# The dodge roll's i-frames, and separate from `invulnerable` for the reason stated
# directly above rather than out of tidiness. Both directions of sharing that flag are
# broken and neither looks like a roll bug: a respawn grace expiring mid-roll would clear
# the roll's invulnerability, and a roll ending inside a respawn grace would clear the
# RESPAWN's — killing a player who had just come back and is still standing where they
# died. One owner each. Written only by PlayerRoll, which clears it in exit() as well as
# on its own timer, so a death mid-roll cannot strand it true.
var rolling_invulnerable := false

# Instance ids of the enemies the swing currently running has already struck. See
# _on_body_entered_attack(), which is where the double-hit actually comes from.
var _swing_hits := {}

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
	inventory_data.inventory_slot_datas.append(SlotData.new(GameItems.get_item(Types.Item.Workbench), 1) as SlotData)
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
	_build_interact_prompt()

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
	input_manager.connect("dodge", Callable(self, "_dodge"))

	resourceManager.connect("resource_removing", Callable(self, "_on_resource_removing"))
	resourceManager.connect("resource_removing_stop", Callable(self, "_on_resource_removing_stop"))
	attack.connect("body_entered", Callable(self, "_on_body_entered_attack"))
	


func set_spawn_position(new_spawn: Vector2) -> void:
	spawn_position = new_spawn


func _on_died():
	if is_dead:
		return
	is_dead = true

	# After the guard, so one death is one death. Recorded rather than punished: respawn is free
	# (see respawn() below), so this is on the score card as texture — "day 14, never died" is a
	# different run from "day 14, died nine times", and nothing else records the difference.
	var run_stats := RunStats.find(self)
	if run_stats != null:
		run_stats.record_death()

	respawn()


# Forager-style: death costs you the trip back, not your inventory. Full heal at the
# spawn point plus a grace window so the enemy that killed you cannot immediately
# kill you again while you are still standing in its lap.
func respawn() -> void:
	input_manager.disable_input = true
	# Through the machine rather than only writing the three properties below, because a swing
	# or a roll is now more than the properties: PlayerAttack holds a live active window and
	# PlayerRoll holds `rolling_invulnerable`. Dying mid-roll used to be impossible to reach
	# and is now one input away, and a roll whose exit() never ran leaves the player
	# permanently invulnerable — the one bug in this file that nothing on screen would report.
	# change_to() runs the outgoing state's exit(), which is exactly the teardown wanted here.
	state_machine.change_to("PlayerIdle")
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
	

## Parented to the TileMap, exactly as ResourceManager2 parents GatherProgress: the bubble is
## `top_level`, so the parent decides nothing about where it draws, and putting it under the
## tilemap keeps every world-space indicator in one branch instead of scattering them across
## the Player.
##
## Guarded rather than assumed. `tilemap` is an @export wired in main.tscn, and a Player stood
## up outside it (a test, a scratch scene) has none — a raise here would abort `_ready()` after
## the input connections and leave a player that cannot be controlled, which is a much worse
## failure than going without a prompt.
func _build_interact_prompt() -> void:
	if tilemap == null or tilemap.tileMap == null:
		push_warning("Player: no tilemap, the interact prompt was not created")
		return
	interact_prompt = InteractPrompt.new()
	interact_prompt.name = "InteractPrompt"
	tilemap.tileMap.add_child(interact_prompt)


## Both handlers below stamp the highlight through the same `is_interactable` gate `_process`
## uses. Without it they are a frame's worth of disagreement: the area reports a body, this
## draws a highlight under it, and `_process` then decides it is not something that opens and
## takes the highlight away again.
func on_interact(body: Node2D):
	if not chests.has(body):
		chests.append(body)

	if InteractPrompt.is_interactable(nearest_chest):
		tilemap.set_interact_highlight(nearest_chest.position)
	pass

func on_interact_exit(body: Node2D):
	chests.erase(body)

	if chests.size() == 0:
		nearest_chest = null
		# Only this system's own cell. remove_highlight() wipes the whole of layer 3,
		# which is also where the gather selector lives (gather-3zg.6).
		tilemap.clear_interact_highlight()

	if InteractPrompt.is_interactable(nearest_chest):
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
	# The third way an outside system used to end a swing early, and the least obvious: this
	# plays Gather straight over whatever the AnimationPlayer is running, so pressing the
	# destroy key mid-swing replaced the swing's animation and `_physics_process` read the
	# substitution as the swing having finished. Declining the press for the ~0.2s of a live
	# swing costs the player nothing — the tile is still there afterwards — and is the same
	# rule the gather release above follows, through the same predicate.
	if not release_may_stop_animation(_state()):
		return

	$Gather.visible = true
	#$AnimatedSprite2D.play("Gathering")
	if not $AnimatedSprite2D.flip_h:
		$AnimationPlayer.play("Gather")
	else:
		$AnimationPlayer.play("Gather_left")
		
	destroy_manager.start_removing_resource()
	pass	

## Whether a hit gets through, given the four flags that can stop it.
##
## Static and taking every input as an argument for the same reason `build_payload()` below is
## (see the header of the save-payload section): Player is scene-backed — half its @onready
## fields reach up into ../../Systems and ../../UI — so a headless test cannot stand one up,
## and this rule is exactly the part worth pinning. The dodge roll's whole value is that its
## i-frames stop a hit, and there is no other way to assert that outside a running game.
##
## Four flags rather than one, each with exactly one owner: `is_dead` the death sequence,
## `invulnerable` the respawn grace, `rolling_invulnerable` PlayerRoll, `god_mode` the debug
## panel. The declarations say why merging any two of them is a bug.
static func hit_lands(
		dead: bool, respawn_grace: bool, rolling: bool, cheat: bool) -> bool:
	return not (dead or respawn_grace or rolling or cheat)


## Whether an input release from OUTSIDE the state machine may stop the AnimationPlayer.
##
## Static for the reason above, and this one is the rule that makes a swing atomic: false
## while a swing is in its active frames, true for everything else — including a null state,
## because a machine that has not readied yet must not leave a looping Gather animation
## running forever.
static func release_may_stop_animation(state: PlayerState) -> bool:
	return state == null or not state.owns_swing()


## Whether a dodge press may start a roll.
##
## Static for the reason above. Every refusal is gathered here rather than left as sequential
## early returns in `_dodge()`, because the ORDER does not matter but the completeness does: a
## missing one is a roll that cancels a committed swing, fires while the player is being
## teleported back to spawn, or ignores its own cooldown — and the last of those is a free
## second of invulnerability on tap.
static func dodge_allowed(
		state: PlayerState, roll_ready: bool, dead: bool, input_disabled: bool) -> bool:
	if dead or input_disabled:
		return false
	if state != null and (state.owns_swing() or state.is_committed()):
		return false
	return roll_ready


## Records `id` as struck by the swing currently running, and answers whether this is the
## FIRST time it has been struck by it. `seen` is mutated.
##
## Static and taking the dictionary for the reason above — the double-hit is otherwise only
## observable by standing an enemy in front of a live Player and watching a health bar.
static func register_swing_hit(seen: Dictionary, id: int) -> bool:
	if seen.has(id):
		return false
	seen[id] = true
	return true


func receive_hit(_force: Vector2, _damage: int):
	if not hit_lands(is_dead, invulnerable, rolling_invulnerable, god_mode):
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

## Clears the record of what the swing about to start has hit. Called by PlayerAttack, which
## is the only thing that knows where a swing begins.
func begin_swing() -> void:
	_swing_hits.clear()


func _on_body_entered_attack(body: Node2D):
	if body is not Enemy:
		return

	# One swing, one hit per enemy. `body_entered` is not once-per-swing: the `Attack` area's
	# POSITION AND ROTATION are both keyframed (main.tscn's Attack / Attack2 sweep it from
	# roughly (-1, 1) to (3, 3) while rotating ~140 degrees), so the area genuinely leaves an
	# enemy and arrives back on it inside one 0.2s animation, and Godot reports each arrival.
	# Against a stationary skeleton that is two hits for one swing, and the second one is
	# invisible in every reading except the health bar dropping twice as fast as the damage
	# the sword claims. The buffered follow-up swing makes this easier to hit, not harder.
	#
	# Keyed on the instance id rather than on the node, so a freed enemy — a kill on the first
	# hit is the common case — cannot keep a reference alive in here until the next swing.
	if not register_swing_hit(_swing_hits, body.get_instance_id()):
		return

	var direction = (body.global_position - global_position).normalized()
	# The equipped sword sets `damage` (PlayerManager.show_slot_data); this used
	# to pass a hardcoded 3, so neither the sword nor any skill reached the enemy.
	body.receive_hit(direction * 100, damage + stats.damage_bonus)
	
## The state currently running, or null. Every gate below goes through this rather than
## reaching into `state_machine.state` directly, so a machine that has not readied yet is one
## check rather than five.
func _state() -> PlayerState:
	return state_machine.state if state_machine != null else null


func _attack():
	if is_dead:
		return
	# A roll is a commitment. Letting an attack cut out of one would make the roll the cheapest
	# way to reposition mid-fight with nothing charged for it, which is the opposite of what
	# its recovery exists to do.
	var current := _state()
	if current != null and current.is_committed():
		return
	state_machine.change_to("PlayerAttack")


## Shift, or the ROLL button on the touch overlay.
##
## All three refusals are gates in front of the transition rather than early exits inside the
## state, and that ordering is the point: `change_to("PlayerRoll")` runs the OUTGOING state's
## exit() before PlayerRoll's enter() gets to object, so a roll refused from inside enter()
## would still have torn down a gather the player is holding — for a roll that never happened.
## Not out of a live swing: the blow is mid-flight, and cancelling it would take the damage off
## an attack the player has already committed to and will still pay the recovery for. Rolling
## out of that swing's RECOVERY is fine and deliberate — `owns_swing()` is false by then, and a
## combat system that will not let you leave after the hit has landed punishes attacking at all.
func _dodge():
	if not dodge_allowed(_state(), roll_state.can_roll(), is_dead, input_manager.disable_input):
		return

	state_machine.change_to("PlayerRoll")


## Stops the mining work order, and hands the animation question to the state machine.
##
## The unconditional `animation_player.stop()` this replaces is what made a swing breakable.
## It fires on any `gather` RELEASE, and on a phone `gather` and `attack` come off the SAME
## physical button — `ui/mobile_controls.gd`'s one contextual primary resolves to either — so
## lifting the finger that had just started a swing stopped the swing's own animation a couple
## of frames in, and `_physics_process` then read the quiet AnimationPlayer as "the swing is
## over" and disarmed the hitbox. A tap on HIT did no damage, with nothing anywhere reporting
## why.
##
## The stop is still needed for its actual job — Gather and Gather_left are authored
## `loop_mode = 1`, so they never end on their own — which is why this asks the state rather
## than simply deleting the line.
func _gather_input_release():
	resourceManager.stop_removing_resource()

	if not release_may_stop_animation(_state()):
		return
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

	# Annotated rather than inferred: `v` is an untyped field (it predates this file's typed
	# style), so `:=` here fails to compile with "cannot infer the type of walk".
	var walk: Vector2 = v * MOVE_SPEED * stats.move_speed_mult
	v = Vector2.ZERO

	# The running state gets the last word. Two states need to overrule ordinary walking and
	# they need it in opposite directions — PlayerAttack slows the player without steering
	# them, PlayerRoll ignores the input entirely and drives its own burst — so this is a
	# vector hook rather than a speed multiplier. Every other state returns the argument
	# unchanged, which is why nothing else in the project had to learn about it.
	var current := _state()
	velocity = current.movement_velocity(walk) if current != null else walk

	move_and_slide()
	
func _process(_delta):
	# The second of the two independent hit-stop tickers (the other is world/camera.gd). Two,
	# because Engine.time_scale is global and a stuck one has no in-game way out: neither node
	# being freed, disabled or having its processing turned off can strand the clock. It is a
	# bool test while no dip is running. See the hit-stop section of systems/juice.gd.
	Juice.tick()

	# Duck-typed, and gated on the SAME predicate the highlight and the prompt below are.
	#
	# This used to be `if nearest_chest is TestChest ... elif nearest_chest is CraftingStation`,
	# which is why "every interactable" was false: anything else that walked into the Interact
	# area became `nearest_chest`, got a highlight tile stamped under it and a prompt over it,
	# and then did nothing at all when the key was pressed — with no error and nothing on screen
	# admitting it. Adding an interactable also meant remembering to edit a chain in a file about
	# the player, which is the sort of edit that is remembered late. Asking whether the thing can
	# be interacted with is both the smaller rule and the honest one.
	#
	# The old shape also `return`ed out of _process on a press with nothing in range, skipping
	# the prune and the nearest-search for that frame.
	if Input.is_action_just_pressed("action") and InteractPrompt.is_interactable(nearest_chest):
		nearest_chest.player_interact()
		if interact_prompt != null:
			# The bubble reacts to the press landing, so a press that registered is visibly
			# different from one aimed a tile short.
			interact_prompt.react()

	# A chest freed while still inside the Interact area never fires body_exited, so `chests`
	# can hold a freed object. Reading .position off one errors every frame; dropping them
	# here is what keeps nearest_chest honest (gather-3zg.6).
	var live_chests: Array = []
	for chest in chests:
		if is_instance_valid(chest):
			live_chests.append(chest)
	if live_chests.size() != chests.size():
		chests = live_chests

	# Recomputed from nothing every frame rather than left to decay: `nearest_chest` used to be
	# written only when something beat the running best, so a target that was freed, or that
	# stopped qualifying, stayed nearest until the area happened to empty.
	var nearest = null
	var nearestDistance = 1000000
	for chest in chests:
		# The gate. A body in reach that cannot be opened is not a target, so it can neither
		# take the highlight off the station standing next to it nor raise a prompt that lies.
		if not InteractPrompt.is_interactable(chest):
			continue
		var tilePos = tilemap.tileMap.local_to_map(chest.position)
		var direction = global_position - tilemap.tileMap.map_to_local(tilePos)
		var distance = direction.length()
		if distance < nearestDistance:
			nearestDistance = distance
			nearest = chest
	nearest_chest = nearest

	if nearest_chest:
		# set_interact_highlight is idempotent, so the common case — same chest, same cell —
		# is a comparison rather than a wipe-and-restamp of the whole layer every frame.
		# clear_interact_highlight touches only this system's own cell; remove_highlight() wipes
		# the whole of layer 3, which is also where the gather selector lives (gather-3zg.6).
		tilemap.set_interact_highlight(nearest_chest.position)
	else:
		tilemap.clear_interact_highlight()

	if interact_prompt != null:
		# Cheap to call every frame with the same target — only a CHANGE of target costs
		# anything. Driven from the same `nearest_chest` the highlight is, so the two can never
		# point at different things.
		interact_prompt.point_at(nearest_chest)
	pass
	
func get_drop_position() -> Vector2:
	var direction = -camera.global_position
	return camera.global_position + direction
	
func _physics_process(_delta):
	#$AnimatedSprite2D.play("Idle")
		
	_process_movement()

	var current := _state()
	var swinging := current != null and current.owns_swing()

	if not $AnimationPlayer.is_playing() and not swinging:
		# `swinging` is what makes the swing atomic on this side. This block used to read a
		# quiet AnimationPlayer as "nothing is being swung", which is true of the net and false
		# of the sword the moment anything else stops or replaces the animation — and three
		# separate things did (see _gather_input_release, _destroy_input_press). PlayerAttack
		# now owns its own active window and takes the hitbox down itself at the end of it;
		# this stays as the backstop for every state that is NOT mid-swing, which is what it
		# was always doing correctly for the net.
		$Attack.visible = false
		$Attack.monitoring = false
		net.visible = false
		# `monitoring`, not `monitorable`. These are opposite directions: `monitoring` is
		# whether THIS area detects bodies, `monitorable` is whether OTHER areas can detect
		# it. Only the first one stops the net catching things, and nothing in the project
		# detects the net area at all, so the old line was inert — this was the backstop
		# that should have closed the window left open when player_net.on_hit's own
		# `monitoring = false` was silently refused mid-callback (gather-uem). Every other
		# one of the six such writes in the project uses `monitoring`; this was the odd one.
		#
		# A direct write is correct here: _physics_process runs outside the query flush, so
		# the physics server is not locked. It is only the body_entered handler that has to
		# defer.
		net.monitoring = false
		net.monitorable = false

	# Facing is frozen for the active frames of a swing. The `Attack` area is authored
	# per-direction — main.tscn has a separate Attack_Left with its own keyframed positions —
	# so flipping the sprite mid-swing points the sprite one way and leaves the hitbox sweeping
	# the other. The player sees a sword swung to their left and an enemy on their left taking
	# no damage, which reads as the hit detection being broken rather than as them having
	# turned. Facing is free again the instant the blow has landed.
	if velocity.x != 0 and not swinging:
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

