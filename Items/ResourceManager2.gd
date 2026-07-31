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
const MAX_RESOURCE_NODES := 60

# Floor on gather time so a fast tool can never hand Timer a zero wait_time.
const MIN_GATHER_TIME := 0.1

var hold_timer = Timer.new()
var removing_info
var is_holding_e = false
var removing_node

# Pickaxe driving the current gather, so the drop roll can apply its tier bonus.
var removing_tool: GameItemPickaxe

func _ready():
	add_to_group("SaveLoad")
	randomize()
	tile_map_handler.resource_found.connect(_resource_found)
	hold_timer.wait_time = 1
	hold_timer.one_shot = true
	
	curent_resources.append(resources.Get(Types.Item.StoneResourceTest))
	curent_resources.append(resources.Get(Types.Item.Tree))
	
	add_child(hold_timer)
	hold_timer.connect("timeout", Callable(self, "_on_hold_timer_timeout"))
	
func add_resource(type: Types.Item):
	curent_resources.append(resources.Get(type))
	
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

func add_random_resource():
	if tile_map_handler.count_resource_nodes() >= MAX_RESOURCE_NODES:
		return

	var random_tile = tile_map_handler.get_random_tile()
	var random_resource = get_random()

	if random_tile != null and random_resource != null:
		set_resource(random_tile, random_resource)

func set_resource(location, resource: GameResource):
	#tile_map_handler.set_game_resource(location, resource.tile_source_id, resource.atlas_location)
	emit_signal("resource_added", location, resource)

func remove_resource(location, resource: GameResource):
	var bonus_chance := removing_tool.bonus_yield_chance if removing_tool else 0.0

	for _i in resource.roll_yield(bonus_chance):
		PickUpManager.create_pickup(GameItems.get_item(resource.drop), location)

	if resource.roll_secondary_drop():
		PickUpManager.create_pickup(GameItems.get_item(resource.secondary_drop), location)

	level_up_manager.add_xp(resource.xp)
	GameSoundManager.stop_gathering_sound()
	#tile_map_handler.clear_tile(location)
	emit_signal("resource_removed", location, resource)

func start_removing_resource(pickaxe: GameItemPickaxe):
	is_holding_e = true
	removing_tool = pickaxe
	hold_timer.wait_time = max(MIN_GATHER_TIME, pickaxe.power)
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
		
	
func stop_removing_resource():
	is_holding_e = false
	hold_timer.stop()
	if removing_info != null:
		GameSoundManager.stop_gathering_sound()
		emit_signal("resource_removing_stop", removing_info.location, removing_info.resource)
	
func _on_hold_timer_timeout():
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
		
