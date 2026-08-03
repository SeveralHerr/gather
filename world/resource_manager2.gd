extends Node
class_name ResourceManager2

signal resource_added(location: Vector2i, resource)
signal resource_removed(location: Vector2i, resource)
signal resource_removing(location: Vector2i, resource)
signal resource_removing_stop(location: Vector2i, resource)

@export var resources: Resources
@export var curent_resources = []
@export var tile_map_handler: TileMapHandler
@export var player: Player
@export var level_up_manager: LevelUpManager
# Assigned in main.tscn. No longer read here — shaking goes through Juice.shake(), which
# finds the camera by group so no caller has to carry a reference — but the export is kept
# because clearing it is a scene edit for no gain.
@export var camera: Camera

# Ceiling on live resource nodes. The spawn timer never stops, so without this the
# island saturates: every walkable tile ends up occupied, get_random_tile burns all
# of its retries every tick, and the player has nowhere left to build.
#
# It is a density rather than a flat number because the island is no longer a fixed
# size - land is bought, and a flat cap would leave every parcel after the first one
# barren while the starting island stayed as crowded as ever.
const RESOURCE_NODES_PER_LAND_TILE := 0.25
const MIN_RESOURCE_CAP := 40

# Floor on gather time so a fast tool can never hand Timer a zero wait_time.
const MIN_GATHER_TIME := 0.1

# How close the player has to stand for a scene-backed node to count as the gather
# target. Both branches of start_removing_resource use it; only one of them used to.
const SCENE_TILE_REACH := 20.0

# How long the scene-node break effect runs before the resource is actually removed. Defined
# as the juice constant rather than a second literal, because GameSceneResource's break pop is
# timed to finish exactly as the node goes away and the two drifting apart would either cut
# the pop off or leave a fully-faded node sitting there.
const SCENE_BREAK_TIME := Juice.NODE_BREAK_TIME

# Everything a wooden pickaxe can be pointed at from the first frame. Coal and copper are
# here rather than behind a skill so a player who pushes any other branch is not left with
# a pickaxe and nothing but trees and stone to hit. The higher tiers (iron, gold) are still
# skill-gated - see SkillTree.
#
# Copper rather than iron is the free ore because copper is the *lower* tier everywhere
# else: the copper pickaxe is the slower one (items.gd) and CopperBar smelts a full skill
# tier before IronBar (recipes.gd). Shipping iron unlocked and copper gated inverted that -
# a fresh player mined iron ore they could not smelt for two Industry tiers while the ore
# they needed first did not exist in the world at all. Iron now appears exactly when
# `smelting` makes it useful.
#
# A constant rather than a literal in _ready() because it is also the answer to "what does
# the spawn roll actually consider early on", which is the half of any spawn-weight
# question that is easy to forget: an island themed around a locked resource plays
# unthemed until the skill is bought.
const STARTING_RESOURCES := [
	Types.Item.StoneResourceTest,
	Types.Item.Tree,
	Types.Item.StoneResource,
	Types.Item.CoalResource,
	Types.Item.CopperResource,
]

var hold_timer = Timer.new()
var removing_info
var is_holding_e = false
var removing_node

# Pickaxe driving the current gather, so the drop roll can apply its tier bonus.
var removing_tool: GameItemPickaxe

var gather_progress: GatherProgress

# --- Per-swing gather feedback ---
#
# A hold runs hold_timer for the pickaxe's whole gather time and, until this, produced no
# visual event at all until it fired. Two seconds of a filling bar is where a young player's
# attention goes, so the hold is divided into discrete swings that each land: a squash on the
# node (scene-backed nodes only — see below), a chip burst, a pulse on the bar and a small
# camera tick.
#
# Scheduled off hold_timer's own elapsed time rather than a second Timer, so the cadence
# cannot drift from the gather it is decorating and a Swift Hands multiplier changes both at
# once. `_process` already runs for the progress bar, so this adds an int compare per frame
# and no allocation.
var _swing_interval := 0.0
var _next_swing_at := 0.0

# Two persistent emitters, positioned per event and restarted, rather than an instance per
# swing. `amount` is fixed on each because writing it reallocates the particle buffer, and a
# gather does that several times a second. Neither is ever freed and neither is ever
# duplicated, so they cost exactly two nodes for the life of the session.
var _chips: GPUParticles2D
var _burst: GPUParticles2D

const HIT_PARTICLES := preload("res://world/vfx/hit_particles.tscn")

func _ready():
	add_to_group("SaveLoad")
	randomize()
	tile_map_handler.resource_found.connect(_resource_found)
	hold_timer.wait_time = 1
	hold_timer.one_shot = true

	for starting_resource in STARTING_RESOURCES:
		add_resource(starting_resource)

	add_child(hold_timer)
	hold_timer.connect("timeout", Callable(self, "_on_hold_timer_timeout"))

	# Parented to the tilemap so it sits in the world next to the node being
	# gathered rather than on the HUD.
	gather_progress = GatherProgress.new()
	gather_progress.name = "GatherProgress"
	tile_map_handler.tileMap.add_child(gather_progress)

	_chips = _make_emitter("GatherChips", Juice.GATHER_CHIP_AMOUNT, Juice.GATHER_CHIP_LIFETIME)
	_burst = _make_emitter("GatherBurst", Juice.GATHER_BURST_AMOUNT, Juice.GATHER_BURST_LIFETIME)


## One of the two shared emitters. Parented to the tilemap for the same reason
## GatherProgress is — it belongs beside the node being mined, not on the HUD — and
## `top_level` so it is positioned in world space rather than in tilemap-local space.
func _make_emitter(emitter_name: String, amount: int, lifetime: float) -> GPUParticles2D:
	var emitter: GPUParticles2D = HIT_PARTICLES.instantiate()
	emitter.name = emitter_name
	emitter.top_level = true
	emitter.one_shot = true
	emitter.explosiveness = 1.0
	emitter.amount = amount
	emitter.lifetime = lifetime
	emitter.emitting = false
	# Below the drops (z_index 1), not above them. See Juice.PARTICLE_Z_INDEX — at 60 the
	# break burst covered the very items the break had just produced.
	emitter.z_index = Juice.PARTICLE_Z_INDEX
	tile_map_handler.tileMap.add_child(emitter)
	return emitter


## The gather chips, for anything that swings at a resource without being the player.
##
## Public because a BoneWorker fells trees on its own and its swings have to look like the
## player's; the alternative was a second GPUParticles2D on every worker, drifting from this
## one the first time GATHER_CHIP_AMOUNT changed. One emitter, one look, one place to tune.
func emit_gather_chips(world_position: Vector2) -> void:
	_emit_at(_chips, world_position)


func _emit_at(emitter: GPUParticles2D, world_position: Vector2) -> void:
	if emitter == null:
		return
	emitter.global_position = world_position
	# restart() rather than `emitting = true`: a one-shot emitter that is already running
	# ignores the assignment, which would swallow every swing after the first.
	emitter.restart()


func _process(_delta):
	if not is_holding_e or removing_info == null or hold_timer.is_stopped():
		return

	# Read from the timer itself so the bar tracks the equipped pickaxe's real
	# gather time instead of a duplicated constant.
	# Explicitly typed: `hold_timer` is an untyped var, so its properties come back as Variant
	# and an inferred `:=` here does not compile.
	var wait: float = hold_timer.wait_time
	var elapsed: float = wait - hold_timer.time_left
	gather_progress.set_progress(elapsed / wait)

	# `while`, not `if`: a frame long enough to span two swings (a hitch, or a hit-stop
	# ending) must not silently drop one and leave the schedule permanently behind.
	while _swing_interval > 0.0 and elapsed >= _next_swing_at and _next_swing_at < wait:
		_next_swing_at += _swing_interval
		_swing()


## One blow lands. Everything here is per-swing rather than per-frame, roughly every
## Juice.GATHER_SWING_INTERVAL seconds.
func _swing() -> void:
	Juice.shake(self, Juice.Shake.TINY)

	if gather_progress != null:
		gather_progress.pulse()

	# The two representations, and the honest difference between them:
	#
	#  * A GameSceneResource is a real node, so it can be squashed and recoiled.
	#  * An ordinary layer-1 tilemap cell is a rectangle of atlas drawn by the TileMapLayer.
	#    It has no transform, no modulate and no material, so THERE IS NOTHING TO ANIMATE.
	#    Making the tile itself react would mean authoring a per-swing atlas frame for every
	#    resource, which is a tileset change rather than a code one. It gets the chips, the
	#    bar pulse and the camera tick instead — everything that lives beside the cell.
	if removing_node != null and is_instance_valid(removing_node) and removing_node is GameSceneResource:
		removing_node.hit_react()

	if removing_info != null:
		_emit_at(_chips, world_position_of(removing_info.location))


func _begin_progress():
	if removing_info != null:
		gather_progress.begin(removing_info.location)


## Makes a resource type eligible for the spawn timer. Idempotent on purpose: the
## same type arrives from the starting set, from a skill purchase and from a loaded
## save, and a duplicate entry would silently double that resource's spawn weight.
func add_resource(type: Types.Item):
	var resource := resources.Get(type)
	if resource == null or curent_resources.has(resource):
		return
	curent_resources.append(resource)


## Live-node ceiling for one region's current size. Per region rather than per map: a
## shared ceiling scaled against total grass means every island revealed raises the home
## island's budget too, and the timer then spends that budget wherever it likes.
func resource_cap(region: LandRegion = null) -> int:
	if tile_map_handler == null:
		return MIN_RESOURCE_CAP
	if region == null:
		region = tile_map_handler.home_region
	var land_tiles: int = tile_map_handler.count_land_tiles_in(region)
	return maxi(region.min_resources, int(land_tiles * region.resource_density))


## How full a stretch of land is when the player first sets foot on it, and the cap on
## how much work one seeding pass will do.
const SEED_FILL_RATIO := 0.7
const SEED_ATTEMPT_LIMIT := 240


## Fills the island up to SEED_FILL_RATIO of its cap in one go.
##
## The spawn timer places one node every eight seconds, which is the right rate for
## *replacing* what the player clears and completely the wrong one for stocking ground
## nobody has stood on yet: a fresh island opened with a single tree, and a parcel
## bought for 31 gold stayed empty grass for the better part of ten minutes. Called
## once after the island is generated, and again whenever land is bought.
## Progress is counted from what add_random_resource() reports, NOT from the node
## census. The census cannot see a scene-backed node on the frame its cell is written,
## so treating a flat census as "the island is full" ended the first seeding pass at
## six nodes — the moment the weighted roll first came up scene stone.
func seed_island(region: LandRegion = null) -> void:
	if tile_map_handler == null:
		return
	if region == null:
		region = tile_map_handler.home_region

	var target := int(resource_cap(region) * SEED_FILL_RATIO)
	var placed := tile_map_handler.count_resource_nodes_in(region)
	var attempts := 0

	while placed < target and attempts < SEED_ATTEMPT_LIMIT:
		attempts += 1
		if add_random_resource(region):
			placed += 1


## Rolls one resource against the unlocked set, with `weights` overriding the global
## per-type spawn weight for the region being stocked.
func get_random(weights: Dictionary = {}):
	if curent_resources.is_empty():
		return null

	var total_weight := 0.0
	for resource in curent_resources:
		total_weight += _weight_of(resource, weights)

	# An override that zeroes every unlocked type means "nothing grows here", which is how
	# the boss arena stays clear. This used to fall through to a uniform pick over the
	# whole set, turning that instruction into precisely its opposite.
	if total_weight <= 0.0:
		return null

	var roll := randf() * total_weight
	for resource in curent_resources:
		roll -= _weight_of(resource, weights)
		if roll <= 0.0:
			return resource

	return curent_resources[curent_resources.size() - 1]


static func _weight_of(resource: GameResource, weights: Dictionary) -> float:
	return max(0.0, weights.get(resource.type, resource.spawn_weight))

## Returns whether a node was actually placed. The caller cannot infer that from the
## node census: a scene-backed resource (StoneResourceTest) becomes a GameSceneResource
## child of the TileMap only after the engine instantiates the scene tile, so the census
## still reads the old value on the same frame the cell was written.
func add_random_resource(region: LandRegion = null) -> bool:
	if tile_map_handler == null:
		return false

	# No region named means the ambient respawn timer, which restocks wherever the
	# world is thinnest rather than one fixed island.
	if region == null:
		region = pick_ambient_region()
		if region == null:
			return false

	if tile_map_handler.count_resource_nodes_in(region) >= resource_cap(region):
		return false

	var random_tile = tile_map_handler.get_random_tile_in(region)
	var random_resource = get_random(region.spawn_weights)

	if random_tile == null or random_resource == null:
		return false

	set_resource(random_tile, random_resource)
	return true


## Which region the respawn timer restocks this tick, weighted by how much land each one
## has - otherwise a six-tile grove is restocked as often as the whole mainland, and the
## mainland goes bare. Regions that opt out are never picked, which is what keeps a boss
## arena clear without the timer needing to know what a boss is.
##
## An island the player cannot walk to yet IS picked, and deliberately: it was stocked at
## generation and it has to stay stocked, or the grove the player has been saving up for is
## a thinning one by the time they arrive. See LandRegion.connected - that gate is the enemy
## spawner's now, not this one's.
func pick_ambient_region() -> LandRegion:
	if tile_map_handler == null:
		return null

	var eligible: Array[LandRegion] = []
	var tile_counts := []
	var total := 0

	for region in tile_map_handler.regions:
		if not region.accepts_ambient_resources():
			continue
		var tiles: int = tile_map_handler.count_land_tiles_in(region)
		if tiles <= 0:
			continue
		eligible.append(region)
		tile_counts.append(tiles)
		total += tiles

	if total <= 0:
		return null

	var roll := randi() % total
	for i in eligible.size():
		roll -= tile_counts[i]
		if roll < 0:
			return eligible[i]

	return eligible[eligible.size() - 1]

func set_resource(location, resource: GameResource):
	#tile_map_handler.set_game_resource(location, resource.tile_source_id, resource.atlas_location)
	emit_signal("resource_added", location, resource)

## Global position of a gather target. `location` is not one thing: the tilemap branch
## hands over a map coordinate (Vector2i from get_location_of_nearby_resource), while the
## scene-tile branch hands over the node's position in tilemap space. Both have to become
## a global position before anything world-space - the xp splash - can be put there.
func world_position_of(location) -> Vector2:
	# Untyped on purpose: tileMap is a TileMap/TileMapLayer and map_to_local() is not on
	# Node2D, so a narrower static type here would fail to compile.
	var tile_map = tile_map_handler.tileMap if tile_map_handler else null

	if location is Vector2i:
		if tile_map == null:
			return Vector2(location)
		return tile_map.to_global(tile_map.map_to_local(location))

	var local := Vector2(location.x, location.y)
	if tile_map == null:
		return local
	return tile_map.to_global(local)


func remove_resource(location, resource: GameResource):
	var bonus_chance := removing_tool.bonus_yield_chance if removing_tool else 0.0
	# Bountiful Harvest stacks on top of whatever the pickaxe tier already gives.
	if player:
		bonus_chance += player.stats.bonus_yield_chance

	for _i in resource.roll_yield(bonus_chance):
		PickUpManager.create_pickup(GameItems.get_item(resource.drop), location)

	if resource.roll_secondary_drop():
		PickUpManager.create_pickup(GameItems.get_item(resource.secondary_drop), location)

	level_up_manager.add_xp(resource.xp, world_position_of(location))
	GameSoundManager.stop_gathering_sound()
	#tile_map_handler.clear_tile(location)
	emit_signal("resource_removed", location, resource)

## Emits the stop for whatever is being gathered right now and forgets it, so the two
## tilemap cells main.gd wrote for that target are always undone by someone.
##
## start_removing_resource() used to overwrite removing_info outright. That orphaned the
## previous tile's layer-3 selector and its layer-1 mid-gather frame with no code path
## left holding a reference to either, and hold_timer was restarted so the tile was never
## gathered away and cleared that way either. The mid-gather cells are *animated in the
## tileset* (source 4, 4:3 is four frames for Tree, 3:5 is five for StoneResource) and
## Godot loops a tile animation for as long as the cell holds that atlas coord — so an
## orphaned cell is a resource that visibly mines itself forever.
func _release_target() -> void:
	if removing_info != null:
		emit_signal("resource_removing_stop", removing_info.location, removing_info.resource)
	removing_info = null
	# Never carried across a retarget: it is only ever set by the scene-tile branch, and
	# a stale one sent the next tile-based gather down the scene path at _on_hold_timer_timeout.
	removing_node = null


func start_removing_resource(pickaxe: GameItemPickaxe):
	# Before anything else, and before the lookup below overwrites removing_info: a second
	# press is cheap to come by (PlayerGather.enter() starts a gather on every entry), and
	# the previous target's cells have to be handed back first.
	_release_target()

	is_holding_e = true
	removing_tool = pickaxe
	# Swift Hands scales the tool's own gather time. The MIN_GATHER_TIME floor still
	# applies, so no stack of speed skills can hand Timer a zero wait_time.
	var speed_mult: float = player.stats.gather_speed_mult if player else 1.0
	hold_timer.wait_time = max(MIN_GATHER_TIME, pickaxe.power * speed_mult)
	hold_timer.start()

	# Divide the hold into swings. The cadence is what stays roughly constant across pickaxe
	# tiers, so a better tool reads as "fewer swings to break it" rather than as the same
	# animation played faster.
	var gather_seconds: float = hold_timer.wait_time
	_swing_interval = gather_seconds / float(Juice.swings_for(gather_seconds))
	# Zero, not one interval: the first blow lands on the frame the key goes down. The press
	# is the moment that has to feel answered, and waiting 0.4s for the first chip to fly
	# reintroduces exactly the dead interval this is here to remove.
	_next_swing_at = 0.0

	removing_info = tile_map_handler.get_location_of_nearby_resource(player.global_position)
	if removing_info != null:
		if removing_info.resource.type == Types.Item.StoneResourceTest:
			var node = tile_map_handler.get_nearest_scene_tile()
			# get_nearest_scene_tile() searches the whole island, so it needs the same
			# reach check the else branch below already applies. Without it a cell that
			# merely resolves to StoneResourceTest by atlas coords retargets the gather
			# onto a scene stone the player may be nowhere near, and draws the selector
			# there.
			if node is GameSceneResource and (player.global_position - node.position).length() < SCENE_TILE_REACH:
				removing_info.location = node.position
				removing_info.resource = resources.get_item_or_resource_by_type(node.resource_type)
				removing_node = node
		GameSoundManager.play_gathering_sound(removing_info.resource.sound)

		emit_signal("resource_removing", removing_info.location, resources.get_item_or_resource_by_type(removing_info.resource.type))
		_begin_progress()
		return
	else:
		var node = tile_map_handler.get_nearest_scene_tile()
		if node and node is GameSceneResource:
			#if node.resource_type == removing_info.resource.type:
			if (player.global_position - node.position).length() < SCENE_TILE_REACH:
				removing_info = { "resource" :resources.get_item_or_resource_by_type(node.resource_type),  "location": node.position }
				removing_node = node
			
		if removing_info:
			GameSoundManager.play_gathering_sound(removing_info.resource.sound)
			emit_signal("resource_removing", removing_info.location, removing_info.resource)
			_begin_progress()
		
	
func stop_removing_resource():
	is_holding_e = false
	hold_timer.stop()
	# Stops the swing scheduler as well as the timer. Left running, a release followed by a
	# press on a shorter gather would inherit the old schedule and fire its first swing late.
	_swing_interval = 0.0
	gather_progress.finish()
	if removing_info != null:
		GameSoundManager.stop_gathering_sound()
	# Also nulls removing_info. Leaving it set meant a second stop re-emitted for an
	# already-cleared cell, and main.gd answers a stop by rewriting the resource's idle
	# tile - which resurrected a node that had just been gathered away.
	_release_target()


func _on_hold_timer_timeout():
	gather_progress.finish()
	_swing_interval = 0.0
	if not is_holding_e or removing_info == null:
		return

	# Detach the target before the await below. Both fields are mutable, and all three
	# things that can happen during those 0.3s used to be read back afterwards: a release
	# was ignored and the resource gathered anyway; a retarget stranded the first tile's
	# cells; and a retarget that found nothing left removing_info null, so the resume
	# dereferenced it. That last one aborted the coroutine part-way, and because this
	# method returns void the abort was silent in the web build, leaving hit_particles
	# emitting forever and removing_node still set to mis-route the next gather.
	var info = removing_info
	var node = removing_node
	removing_info = null
	removing_node = null

	# The payoff burst, at the cell that was being worked. Fired for BOTH representations:
	# a tilemap cell cannot pop, but the chips and the shake that mark the moment it gives
	# way can still happen at its world position, and before this a plain tile simply
	# disappeared with no event at all.
	_emit_at(_burst, world_position_of(info.location))

	if node and node is GameSceneResource:
		Juice.shake(self, Juice.Shake.MEDIUM)
		node.break_react()
		node.hit_particles.emitting = true
		await get_tree().create_timer(SCENE_BREAK_TIME).timeout
		# The node can be freed while the timer runs (save load, land regeneration).
		if is_instance_valid(node):
			node.hit_particles.emitting = false
	else:
		# A tile cell breaks a shade more gently than a boulder does.
		Juice.shake(self, Juice.Shake.LIGHT)

	# remove_resource emits resource_removed, which main.gd answers with
	# clear_tile(local_to_map(location)) - that clears both the layer-1 tile and the
	# layer-3 selector at the right cell. The scene branch used to *also* call set_cell
	# with the raw local position, i.e. pixels where map coords were wanted, clearing a
	# cell tens of tiles away. Redundant as well as wrong, so it is gone.
	remove_resource(info.location, info.resource)


func _resource_found( resource: GameResource, location: Vector2i):
	remove_resource(location, resource)


func saveObject() -> Dictionary:
	var current_resource_json = []

	for i in curent_resources.size():
		var json := {
			"type": curent_resources[i].type
		}
	
		# A nested dictionary, not JSON.stringify of one: SaveLoad stringifies the whole
		# payload anyway, so the inner layer was pure overhead and one more failure point.
		# SaveLoad.decode_entries reads both shapes, so older saves still load (gather-usv).
		current_resource_json.append(json)

		
	var dict := {
		"filepath": get_path(),
		"resources": current_resource_json
	}
	return dict
	
func loadObject(loadedDict: Dictionary) -> void:
	curent_resources = []

	# Re-seed the starting set before replaying the save. A type in STARTING_RESOURCES is
	# by definition never lockable, so it must not depend on what a save happened to record
	# - a save written before copper became free would otherwise come back permanently
	# copperless, and no skill grants it any more. add_resource is idempotent, so replaying
	# a saved copy of one of these is harmless.
	for starting_resource in STARTING_RESOURCES:
		add_resource(starting_resource)

	# decode_entries reads both the pre-gather-usv JSON strings and the nested dictionaries
	# written now, and .get keeps a payload with no such key from raising (gather-xc0).
	for node in SaveLoad.decode_entries(loadedDict.get("resources", [])):
		if node.has("type"):
			add_resource(int(node["type"]))
		
