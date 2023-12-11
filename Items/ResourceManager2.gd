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

var hold_timer = Timer.new()
var removing_info
var is_holding_e = false

func _ready():
	add_to_group("SaveLoad")
	randomize()
	tile_map_handler.resource_found.connect(_resource_found)
	hold_timer.wait_time = 1
	hold_timer.one_shot = true
	
	curent_resources.append(resources.Get(Types.Item.StoneResource))
	curent_resources.append(resources.Get(Types.Item.Tree))
	
	add_child(hold_timer)
	hold_timer.connect("timeout", Callable(self, "_on_hold_timer_timeout"))
	
func add_resource(type: Types.Item):
	curent_resources.append(resources.Get(type))
	
func get_random():
	# Get a random index within the range of the array's size
	var random_index = randi() % curent_resources.size()

	# Access the array at the random index
	var random_item = curent_resources[random_index]
	return random_item	

func add_random_resource():
	var random_tile = tile_map_handler.get_random_tile()
	var random_resource = get_random()
	
	if random_tile != null:
		set_resource(random_tile, random_resource)

func set_resource(location, resource: GameResource):
	#tile_map_handler.set_game_resource(location, resource.tile_source_id, resource.atlas_location)
	emit_signal("resource_added", location, resource)

func remove_resource(location, resource: GameResource):
	PickUpManager.create_pickup( GameItems.get_item(resource.drop), location)
	#tile_map_handler.clear_tile(location)
	emit_signal("resource_removed", location, resource)
	
func start_removing_resource(power: int):
	is_holding_e = true
	hold_timer.wait_time = power
	hold_timer.start()
	
	removing_info = tile_map_handler.get_location_of_nearby_resource(player.global_position)
	if removing_info != null:
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
		remove_resource(removing_info.location, removing_info.resource)
		removing_info = null
	
func Test(PlayerPos):
	var resource = tile_map_handler.find_nearest_resource_to_location(PlayerPos)
	
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
		
