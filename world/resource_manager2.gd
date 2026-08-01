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

var hold_timer = Timer.new()
var removing_info
var is_holding_e = false
var removing_node

# Pickaxe driving the current gather, so the drop roll can apply its tier bonus.
var removing_tool: GameItemPickaxe

var gather_progress: GatherProgress

func _ready():
	add_to_group("SaveLoad")
	randomize()
	tile_map_handler.resource_found.connect(_resource_found)
	hold_timer.wait_time = 1
	hold_timer.one_shot = true

	# Everything a wooden pickaxe can be pointed at is here from the first frame.
	# Coal and iron used to wait behind the Iron Age skill, which left a player who
	# pushed any other branch with a pickaxe and nothing but trees and stone to hit.
	# The higher tiers (copper, gold) are still skill-gated - see SkillTree.
	for starting_resource in [
		Types.Item.StoneResourceTest,
		Types.Item.Tree,
		Types.Item.StoneResource,
		Types.Item.CoalResource,
		Types.Item.IronResource,
	]:
		add_resource(starting_resource)

	add_child(hold_timer)
	hold_timer.connect("timeout", Callable(self, "_on_hold_timer_timeout"))

	# Parented to the tilemap so it sits in the world next to the node being
	# gathered rather than on the HUD.
	gather_progress = GatherProgress.new()
	gather_progress.name = "GatherProgress"
	tile_map_handler.tileMap.add_child(gather_progress)


func _process(_delta):
	if not is_holding_e or removing_info == null or hold_timer.is_stopped():
		return

	# Read from the timer itself so the bar tracks the equipped pickaxe's real
	# gather time instead of a duplicated constant.
	gather_progress.set_progress(1.0 - (hold_timer.time_left / hold_timer.wait_time))


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


## Live-node ceiling for the island's current size.
func resource_cap() -> int:
	var land_tiles: int = tile_map_handler.count_land_tiles() if tile_map_handler else 0
	return maxi(MIN_RESOURCE_CAP, int(land_tiles * RESOURCE_NODES_PER_LAND_TILE))


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
func seed_island() -> void:
	var target := int(resource_cap() * SEED_FILL_RATIO)
	var placed := tile_map_handler.count_resource_nodes()
	var attempts := 0

	while placed < target and attempts < SEED_ATTEMPT_LIMIT:
		attempts += 1
		if add_random_resource():
			placed += 1


func get_random():
	if curent_resources.is_empty():
		return null

	var total_weight := 0.0
	for resource in curent_resources:
		total_weight += max(0.0, resource.spawn_weight)

	if total_weight <= 0.0:
		return curent_resources[randi() % curent_resources.size()]

	var roll := randf() * total_weight
	for resource in curent_resources:
		roll -= max(0.0, resource.spawn_weight)
		if roll <= 0.0:
			return resource

	return curent_resources[curent_resources.size() - 1]

## Returns whether a node was actually placed. The caller cannot infer that from the
## node census: a scene-backed resource (StoneResourceTest) becomes a GameSceneResource
## child of the TileMap only after the engine instantiates the scene tile, so the census
## still reads the old value on the same frame the cell was written.
func add_random_resource() -> bool:
	if tile_map_handler.count_resource_nodes() >= resource_cap():
		return false

	var random_tile = tile_map_handler.get_random_tile()
	var random_resource = get_random()

	if random_tile == null or random_resource == null:
		return false

	set_resource(random_tile, random_resource)
	return true

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

func start_removing_resource(pickaxe: GameItemPickaxe):
	is_holding_e = true
	removing_tool = pickaxe
	# Swift Hands scales the tool's own gather time. The MIN_GATHER_TIME floor still
	# applies, so no stack of speed skills can hand Timer a zero wait_time.
	var speed_mult: float = player.stats.gather_speed_mult if player else 1.0
	hold_timer.wait_time = max(MIN_GATHER_TIME, pickaxe.power * speed_mult)
	hold_timer.start()

	removing_info = tile_map_handler.get_location_of_nearby_resource(player.global_position)
	if removing_info != null:
		if removing_info.resource.type == Types.Item.StoneResourceTest:
			var node = tile_map_handler.get_nearest_scene_tile()
			if node is GameSceneResource:
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
			if (player.global_position - node.position).length() < 20:
				removing_info = { "resource" :resources.get_item_or_resource_by_type(node.resource_type),  "location": node.position }
				removing_node = node
			
		if removing_info:
			GameSoundManager.play_gathering_sound(removing_info.resource.sound)
			emit_signal("resource_removing", removing_info.location, removing_info.resource)
			_begin_progress()
		
	
func stop_removing_resource():
	is_holding_e = false
	hold_timer.stop()
	gather_progress.finish()
	if removing_info != null:
		GameSoundManager.stop_gathering_sound()
		emit_signal("resource_removing_stop", removing_info.location, removing_info.resource)

func _on_hold_timer_timeout():
	gather_progress.finish()
	if is_holding_e and removing_info != null:
		#tile_map_handler.find_nearest_resource_to_location(player.global_position)
		if removing_node and removing_node is GameSceneResource:
			var test = removing_node.animated_sprite_2d
			#removing_node.animated_sprite_2d.play("Destroy")
			camera.apply_shake(1)

			removing_node.hit_particles.emitting = true
			await get_tree().create_timer(0.3).timeout
			removing_node.hit_particles.emitting = false
			#removing_node.animated_sprite_2d.animation_finished.connect(_animation_done)
			_animation_done()
			removing_node = null
		else:
			remove_resource(removing_info.location, removing_info.resource)
			removing_info = null
		
func _animation_done():
	#await get_tree().create_timer(0.3).timeout


	remove_resource(removing_info.location, removing_info.resource)

	tile_map_handler.tileMap.set_cell(removing_info.resource.layer, removing_info.location, -1)#, removing_info.resource.atlas_location, removing_info.resource.is_scene_tile)
	removing_info = null
	
func _resource_found( resource: GameResource, location: Vector2i):
	remove_resource(location, resource)


func saveObject() -> Dictionary:
	var current_resource_json = []

	for i in curent_resources.size():
		var json := {
			"type": curent_resources[i].type
		}
	
		current_resource_json.append(JSON.stringify(json))

		
	var dict := {
		"filepath": get_path(),
		"resources": current_resource_json
	}
	return dict
	
func loadObject(loadedDict: Dictionary) -> void:
	curent_resources = []
	for i in loadedDict.resources.size():
		var saved_info = loadedDict.resources[i]
		var json = JSON.new()
		json.parse(saved_info)
		var node = json.get_data()
		
		add_resource(node["type"])
		
